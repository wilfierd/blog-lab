# Bài 3 — Phân tích rủi ro toàn diện

## Nguyên tắc phân loại

```
Rollback   → CODE/CONFIG sai, data không ảnh hưởng → quay về version cũ
Restore    → DATA bị mất hoặc hỏng → lấy lại từ backup
Failover   → INFRASTRUCTURE hỏng, data vẫn còn → chuyển sang node/region khác
Fix-forward → Sự cố nhỏ, rollback nguy hiểm hơn fix → vá thẳng trên production
```

---

## 1. Infrastructure Failures

### 1.1 EC2 instance crash / hang
**Loại:** Failover tự động
- ALB health check `/api/health` fail → ngừng route traffic vào instance đó
- ASG phát hiện unhealthy → terminate và launch instance mới (~3–5 phút)
- Data không bị ảnh hưởng (stateless app, data ở RDS/S3)

**Monitoring alert:** `ALBNoHealthyHosts`, `EC2StatusCheckFailed`

---

### 1.2 EC2 disk full
**Loại:** Fix-forward (không rollback được disk)
```bash
# Phát hiện qua Node Exporter metric: node_filesystem_avail_bytes
# Alert: disk < 10% → cần dọn log hoặc resize volume
du -sh /app/logs/* | sort -rh | head -20
journalctl --vacuum-size=500M

# Resize EBS nếu cần (không cần restart):
aws ec2 modify-volume --volume-id vol-xxx --size 30
sudo growpart /dev/nvme0n1 1
sudo resize2fs /dev/nvme0n1p1
```
**Monitoring alert:** Cần thêm rule `EC2DiskAlmostFull` dựa trên Node Exporter

---

### 1.3 ASG không scale được (quota/AZ hết capacity)
**Loại:** Fix-forward
- AWS báo `InsufficientInstanceCapacity` trong ASG Activity
- Không có alert tự động trong setup hiện tại
- Giải pháp: đổi instance type hoặc AZ trong Launch Template

---

### 1.4 NAT Gateway fail (private subnet mất internet)
**Loại:** Failover / Fix-forward
- EC2 trong private subnet mất kết nối ra ngoài (không pull secrets, không gọi AWS API)
- App vẫn serve request nếu không cần gọi external
- Fix: tạo NAT Gateway mới, update route table

---

## 2. Database Failures

### 2.1 Xóa nhầm dữ liệu (rows/table)
**Loại:** Restore (Point-in-time)
```bash
# Restore RDS về thời điểm trước khi xóa
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier blog-postgres \
  --target-db-instance-identifier blog-postgres-restored \
  --restore-time 2026-04-28T07:55:00Z
```
**RPO:** ~5 phút | **RTO:** 20–30 phút

---

### 2.2 RDS storage full
**Loại:** Fix-forward (không cần restore, cần mở rộng storage)
```bash
# Alert: RDSCriticalFreeStorageSpace (< 2GB) đã được cấu hình
aws rds modify-db-instance \
  --db-instance-identifier blog-postgres \
  --allocated-storage 50 \
  --apply-immediately
```
> Nếu không xử lý kịp, RDS tự chuyển sang read-only → app lỗi khi ghi

---

### 2.3 RDS max connections (db.t3.micro max ~85)
**Loại:** Fix-forward
- **Alert:** `RDSTooManyConnections` (> 80) đã cấu hình
- App dùng connection pool (GORM) — kiểm tra `DB_MAX_OPEN_CONNS`
- Giải pháp ngắn hạn: restart app để giải phóng idle connections
- Giải pháp dài hạn: thêm PgBouncer connection pooler

---

### 2.4 Database corruption
**Loại:** Restore từ snapshot
```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier blog-postgres-new \
  --db-snapshot-identifier <snapshot-id>

# List snapshots có sẵn:
aws rds describe-db-snapshots \
  --db-instance-identifier blog-postgres \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table
```

---

### 2.5 Schema migration sai gây mất/hỏng data
**Loại:** Restore (nguy hiểm nhất)
- Migration chạy `ALTER TABLE DROP COLUMN` hoặc `UPDATE` sai điều kiện
- Data đã thay đổi, không thể rollback migration đơn giản
- **Bắt buộc:** tạo manual snapshot TRƯỚC khi chạy migration

```bash
# Luôn làm trước khi migrate:
aws rds create-db-snapshot \
  --db-instance-identifier blog-postgres \
  --db-snapshot-identifier pre-migration-$(date +%Y%m%d%H%M)
```

---

## 3. Application Failures

### 3.1 Memory leak → OOM Kill
**Loại:** Failover + Fix-forward
- Go runtime metrics: `go_memstats_heap_inuse_bytes` tăng liên tục
- Kernel OOM kill process → systemd tự restart (nếu `Restart=always`)
- App restart giải quyết tạm thời, nhưng vẫn cần fix code
- **Monitoring:** Grafana panel "Go Heap" trong blog-app dashboard

---

### 3.2 Goroutine leak → app treo (hang)
**Loại:** Rollback hoặc restart
- `go_goroutines` tăng không ngừng → eventual deadlock hoặc OOM
- Metric đã có trong Prometheus (`go_goroutines`)
- Rollback về version trước nếu bug từ deploy mới

---

### 3.3 App không kết nối được DB
**Loại:** Fix-forward (kiểm tra config/network)
- Nguyên nhân: sai credentials, security group, RDS restart
- Health check `/api/health` fail → ALB dừng route traffic
- Kiểm tra: Secrets Manager có đúng password không, SG có mở port 5432 không

---

### 3.4 App không kết nối được Redis
**Loại:** Fix-forward (degraded mode)
- Session mới không tạo được, cache miss hoàn toàn
- App vẫn serve được nếu có fallback đọc thẳng DB
- **Alert:** `RedisHighEvictions` hoặc CurrConnections drop về 0

---

### 3.5 S3 permission lỗi (không upload được ảnh)
**Loại:** Fix-forward
- IAM role EC2 thiếu permission `s3:PutObject`
- User thấy lỗi khi upload ảnh, các feature khác vẫn chạy
- Fix: update IAM policy, không cần restore hay rollback

---

## 4. Deploy Failures

### 4.1 Deploy lỗi ngay lập tức (app không start)
**Loại:** Rollback tự động
```bash
# Ansible tự rollback nếu health check fail sau deploy
# Binary cũ được giữ tại /app/blog-app.backup
sudo cp /app/blog-app.backup /app/blog-app
sudo systemctl restart blog
```
**RTO:** < 3 phút

---

### 4.2 Deploy thành công nhưng phát hiện bug sau 2 ngày
**Loại:** Phức tạp — tùy mức độ ảnh hưởng đến data

**Case A: Bug chỉ ảnh hưởng logic/UI, data không bị hỏng**
- Rollback code an toàn
- `blog-app.backup` chỉ lưu version liền trước → nếu đã deploy 2 lần sẽ không rollback được về version cũ
- Cần deploy lại từ binary cũ trên S3

```bash
# List các version binary trên S3
aws s3 ls s3://blog-uploads-<account-id>/releases/ --recursive

# Deploy version cụ thể
ansible-playbook playbooks/deploy.yml -e "binary_version=v1.2.3"
```

**Case B: Bug đã ghi data sai vào DB trong 2 ngày**
- Rollback code không đủ — data đã bị hỏng
- Cần kết hợp: Restore PITR + data migration để fix data sai
- Đây là case khó nhất: phải xác định chính xác data nào bị ảnh hưởng

**Bài học:** Feature flag giúp disable tính năng lỗi mà không cần rollback/restore.

---

### 4.3 Config thay đổi làm app không đọc được secrets
**Loại:** Fix-forward
- Thường xảy ra khi rename secret trong Secrets Manager
- App khởi động thành công nhưng thiếu config → panic hoặc fallback sai
- Fix: cập nhật tên secret trong app config hoặc Secrets Manager

---

## 5. Network Failures

### 5.1 Security Group sai sau Terraform apply
**Loại:** Fix-forward (Terraform revert)
```bash
# Revert terraform change
git revert <commit>
terraform apply
```
- Nếu SG block port 8080 từ ALB → app unreachable nhưng vẫn chạy
- **Alert:** `ALBNoHealthyHosts` fire ngay

---

### 5.2 Tailscale down trên EC2
**Loại:** Degraded monitoring, app không ảnh hưởng
- Prometheus mất target → metrics gap
- App vẫn serve traffic bình thường qua ALB
- Fix: `sudo systemctl restart tailscaled` trên EC2

---

### 5.3 Google OAuth service down
**Loại:** External dependency, không restore được
- User không login được qua Google
- App vẫn chạy, chỉ auth flow bị ảnh hưởng
- Giải pháp: có fallback `/auth/dev-login` cho development
- Production: hiển thị thông báo maintenance cho user

---

## 6. Tình huống đặc biệt: Silent Failure

### 6.1 Backup chạy nhưng snapshot corrupt (không verify)
**Vấn đề:** Backup tồn tại trên S3/RDS nhưng không restore được khi cần
**Phòng ngừa:** Test restore định kỳ (ít nhất 1 lần/tháng)
```bash
# Test restore script local:
./scripts/db-backup-demo.sh
```

### 6.2 Alert rule cấu hình sai → không fire khi cần
**Vấn đề:** Threshold quá cao, metric name sai → alert không bao giờ trigger
**Phòng ngừa:** Test thủ công alert bằng cách gửi fake alert qua Alertmanager API
```bash
curl -X POST http://localhost:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"TestAlert","severity":"critical"}, "annotations":{"summary":"Test"}}]'
```

### 6.3 Log rotation không chạy → disk đầy âm thầm
**Vấn đề:** Loki/promtail log tích lũy, disk monitoring server đầy
**Phòng ngừa:** `node_filesystem_avail_bytes` alert trên monitoring server

---

## Tóm tắt ma trận quyết định

| Tình huống | Rollback | Restore | Failover | Fix-forward |
|---|:---:|:---:|:---:|:---:|
| App crash / hang | | | ✓ | |
| Deploy lỗi ngay | ✓ | | | |
| Deploy lỗi sau 2 ngày (data ok) | ✓ | | | |
| Deploy lỗi sau 2 ngày (data hỏng) | | ✓ | | |
| Xóa nhầm data | | ✓ | | |
| DB corruption | | ✓ | | |
| Migration sai | | ✓ | | |
| EC2 instance hỏng | | | ✓ | |
| Mất cả region | | ✓ | ✓ | |
| Disk full | | | | ✓ |
| Max connections | | | | ✓ |
| S3 permission lỗi | | | | ✓ |
| Security group sai | | | | ✓ |
| Google OAuth down | | | | ✓ |

**Replication ≠ Backup:**
Read replica sao chép realtime — xóa nhầm data thì replica cũng mất ngay. Chỉ snapshot tại thời điểm cố định mới giúp được.
