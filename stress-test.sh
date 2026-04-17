#!/bin/bash
# Script để test Auto Scaling - tạo CPU load cao

echo "=== STRESS TEST AUTO SCALING ==="
echo "Script này sẽ tạo CPU load cao để trigger auto scaling"
echo ""

# Lấy ALB DNS từ terraform output
ALB_DNS=$(cd terraform && terraform output -raw alb_dns_name 2>/dev/null)

if [ -z "$ALB_DNS" ]; then
  echo "Error: Không tìm thấy ALB DNS. Chạy 'terraform output' để kiểm tra."
  exit 1
fi

echo "Target: http://$ALB_DNS"
echo ""
echo "Bắt đầu gửi 1000 requests liên tục..."
echo "Mở AWS Console > EC2 > Auto Scaling Groups để xem instances tăng lên"
echo ""

# Gửi requests liên tục (dùng Apache Bench nếu có, không thì dùng curl loop)
if command -v ab &> /dev/null; then
  echo "Dùng Apache Bench (ab)..."
  ab -n 10000 -c 50 "http://$ALB_DNS/api/health"
else
  echo "Dùng curl loop (cài 'apache2-utils' để dùng ab nhanh hơn)..."
  for i in {1..1000}; do
    curl -s "http://$ALB_DNS/api/health" > /dev/null &
    if [ $((i % 50)) -eq 0 ]; then
      echo "Sent $i requests..."
      sleep 1
    fi
  done
  wait
fi

echo ""
echo "Done! Kiểm tra CloudWatch Metrics:"
echo "AWS Console > CloudWatch > Alarms > blog-cpu-high"
