#!/bin/bash
# Script để test Self-Healing - terminate 1 instance để xem ASG tự tạo lại

echo "=== TEST SELF-HEALING (Auto Recovery) ==="
echo ""

# Lấy ASG name
ASG_NAME=$(cd terraform && terraform output -raw asg_name 2>/dev/null)

if [ -z "$ASG_NAME" ]; then
  echo "Error: Không tìm thấy ASG name"
  exit 1
fi

echo "Auto Scaling Group: $ASG_NAME"
echo ""

# Lấy danh sách instances trong ASG
echo "Đang lấy danh sách instances..."
INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region us-west-2 \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,AvailabilityZone,HealthStatus]' \
  --output table)

echo "$INSTANCES"
echo ""

# Lấy instance ID đầu tiên
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region us-west-2 \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
  echo "Không có instance nào trong ASG"
  exit 1
fi

echo "Sẽ terminate instance: $INSTANCE_ID"
read -p "Tiếp tục? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled"
  exit 0
fi

echo ""
echo "Đang terminate instance $INSTANCE_ID..."
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region us-west-2

echo ""
echo "✅ Instance đã được terminate!"
echo ""
echo "ASG sẽ tự động phát hiện và tạo instance mới trong vài phút."
echo "Theo dõi tại: AWS Console > EC2 > Auto Scaling Groups > $ASG_NAME"
echo ""
echo "Hoặc chạy lệnh này để xem real-time:"
echo "watch -n 5 'aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --region us-west-2 --query \"AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]\" --output table'"
