# Restore Runbook — Blog App

## Thành phần cần backup và restore

| Thành phần | Loại dữ liệu | Backup method | Retention |
|---|---|---|---|
| RDS PostgreSQL | Users, Posts (critical) | AWS automated backup | 7 ngày |
| S3 uploads | Ảnh blog, file người dùng | S3 Versioning + Lifecycle | 90 ngày |
| Redis ElastiCache | Sessions, post cache | Daily snapshot | 3 ngày |
| EC2 app binary | Blog app binary | S3 bucket (versioned) | Indefinite |

---

## Backup theo lịch

| Thành phần | Lịch | Window |
|---|---|---|
| RDS full backup | Hàng ngày tự động | 02:00–03:00 UTC |
| Redis snapshot | Hàng ngày tự động | 01:00–02:00 UTC |
| S3 uploads | Realtime (versioning) | — |
| EC2 binary | Mỗi lần deploy | Ansible deploy task |

---

## Thứ tự restore khi xảy ra sự cố

```
1. RDS PostgreSQL  ←  toàn bộ app phụ thuộc vào đây
2. S3 uploads      ←  file ảnh (độc lập, không block app)
3. Redis           ←  cache/session (app vẫn chạy được nếu không có)
4. EC2 / App       ←  deploy lại sau khi DB đã sẵn sàng
```

---

## Các tình huống và cách xử lý

### Tình huống 1: Xóa nhầm dữ liệu trong DB
**Loại:** Restore từ backup
```bash
# 1. Tạo RDS snapshot thủ công ngay lập tức (bảo toàn trạng thái hiện tại)
aws rds create-db-snapshot \
  --db-instance-identifier blog-postgres \
  --db-snapshot-identifier blog-emergency-$(date +%Y%m%d%H%M)

# 2. Restore point-in-time (chọn thời điểm trước khi xóa)
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier blog-postgres \
  --target-db-instance-identifier blog-postgres-restored \
  --restore-time 2026-04-28T08:00:00Z  # thay bằng thời điểm trước sự cố

# 3. Sau khi instance mới ready (~20 phút), update secrets/connection string
# 4. Verify dữ liệu, đổi tên instance hoặc update config app
```
**RPO:** ~5 phút (automated backup interval)
**RTO:** 20–30 phút (RDS restore time)

---

### Tình huống 2: EC2 instance bị hỏng
**Loại:** Failover tự động (ASG) + không cần restore
```bash
# ASG tự detect và replace instance trong ~3–5 phút
# Nếu cần force:
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id i-xxxxxxxxx \
  --should-decrement-desired-capacity false
```
**RPO:** 0 (stateless app, data ở RDS)
**RTO:** 3–5 phút (ASG launch new instance)

---

### Tình huống 3: Database bị lỗi (corruption)
**Loại:** Restore từ snapshot
```bash
# Restore từ automated backup gần nhất
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier blog-postgres-new \
  --db-snapshot-identifier <snapshot-id>

# List snapshots để chọn:
aws rds describe-db-snapshots \
  --db-instance-identifier blog-postgres \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table
```
**RPO:** Tối đa 24h (automated daily backup)
**RTO:** 20–30 phút

---

### Tình huống 4: Deploy lỗi (app không chạy)
**Loại:** Rollback deploy
```bash
# Ansible rollback tự động nếu health check fail
cd ansible
ansible-playbook playbooks/deploy.yml --tags rollback

# Hoặc rollback thủ công trên EC2:
# binary .backup được giữ lại mỗi lần deploy
sudo systemctl stop blog
sudo cp /app/blog-app.backup /app/blog-app
sudo systemctl start blog
```
**RPO:** 0
**RTO:** < 5 phút

---

### Tình huống 5: Mất toàn bộ stack (region down)
**Loại:** Disaster Recovery
```bash
# 1. Terraform apply trên region mới (us-east-1)
cd terraform/environments/dev
terraform apply -var="region=us-east-1"

# 2. Restore RDS từ cross-region snapshot (nếu có)
# 3. Update DNS / ALB endpoint
# 4. Redeploy app qua Ansible
```
**RPO:** Tùy retention period snapshot
**RTO:** 1–2 giờ

---

## Kiểm tra backup định kỳ

| Kiểm tra | Tần suất | Cách thực hiện |
|---|---|---|
| RDS snapshot tồn tại | Hàng tuần | `aws rds describe-db-snapshots` |
| Thử restore DB local | Hàng tháng | Chạy `scripts/db-backup-demo.sh` |
| Alert monitoring hoạt động | Hàng tuần | Gửi test alert qua Alertmanager API |
| S3 versioning còn object | Hàng tuần | `aws s3api list-object-versions` |
