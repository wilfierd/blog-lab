# Bài 2 — Phân tích RPO và RTO

## Định nghĩa

- **RPO (Recovery Point Objective):** Mất tối đa bao nhiêu dữ liệu nếu xảy ra sự cố — khoảng thời gian từ backup cuối cùng đến lúc sự cố.
- **RTO (Recovery Time Objective):** Hệ thống cần phục hồi trong bao lâu — thời gian từ khi xảy ra sự cố đến khi hoạt động trở lại.

---

## Hệ thống 1: Blog nội bộ công ty

**Mô tả:** Nhân viên dùng để đăng bài nội bộ, chia sẻ kiến thức. Không ảnh hưởng trực tiếp đến doanh thu.

| | Giá trị | Lý do |
|---|---|---|
| **RPO** | 24 giờ | Nội dung blog thay đổi chậm (1–2 bài/ngày). Mất 1 ngày dữ liệu chấp nhận được vì có thể viết lại. |
| **RTO** | 4 giờ | Không urgent — nhân viên có thể làm việc offline trong vài giờ. Cho phép restore có kiểm soát. |

**Backup phù hợp:** Daily backup, giữ 7 ngày.

---

## Hệ thống 2: Website bán hàng

**Mô tả:** Xử lý đơn hàng, thanh toán, tồn kho. Downtime = mất doanh thu trực tiếp.

| | Giá trị | Lý do |
|---|---|---|
| **RPO** | 1 giờ | Mỗi giờ có thể có hàng chục đơn hàng. Mất > 1 giờ dữ liệu là không chấp nhận được về tài chính và uy tín. |
| **RTO** | 30 phút | Mỗi phút downtime = doanh thu mất. SLA thương mại thường yêu cầu < 1 giờ. |

**Backup phù hợp:** Hourly snapshot, replication sang read-replica, multi-AZ RDS.

---

## Hệ thống 3: Quản lý tài liệu nội bộ

**Mô tả:** Lưu hợp đồng, quy trình, tài liệu pháp lý. Không realtime nhưng dữ liệu quan trọng, không thể tạo lại.

| | Giá trị | Lý do |
|---|---|---|
| **RPO** | 4 giờ | Tài liệu thay đổi ít nhưng rất quan trọng — không thể mất quá nửa ngày làm việc. Có thể tạo lại một phần nhưng tốn kém. |
| **RTO** | 2 giờ | Nhân viên cần truy cập tài liệu trong ngày nhưng không cần ngay lập tức. 2 giờ cho phép restore có kiểm tra. |

**Backup phù hợp:** Backup mỗi 4 giờ, giữ 30 ngày, lưu offsite (S3 cross-region).

---

## So sánh tổng hợp

```
Criticality (cao → thấp):
  Website bán hàng  → RPO 1h,  RTO 30min  (mất tiền trực tiếp)
  Quản lý tài liệu  → RPO 4h,  RTO 2h     (quan trọng nhưng không realtime)
  Blog nội bộ       → RPO 24h, RTO 4h     (chấp nhận mất 1 ngày)
```

**Nguyên tắc chung:** RPO và RTO càng nhỏ thì chi phí infrastructure càng cao (multi-AZ, hourly backup, standby replica). Phải cân bằng giữa risk và cost.
