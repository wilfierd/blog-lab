#!/bin/bash
# Scan EC2 instances trong ASG, liệt kê versioned binaries có sẵn để rollback
# Output: in ra GITHUB_STEP_SUMMARY nếu chạy trong GHA, stdout nếu chạy local

set -e

REGION="${AWS_REGION:-us-west-2}"
ASG_NAME="${ASG_NAME:-blog-app-asg}"
APP_NAME="${APP_NAME:-blog-app}"
TARGET_VERSION="${1:-}"  # optional: version muốn rollback (để thêm vào summary)

IN_GHA="${GITHUB_STEP_SUMMARY:+yes}"

write() {
    if [ -n "$IN_GHA" ]; then
        echo "$1" >> "$GITHUB_STEP_SUMMARY"
    else
        echo "$1"
    fi
}

# Lấy danh sách InService instances
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
    --output text --region "$REGION")

if [ -z "$INSTANCE_IDS" ]; then
    write "❌ Không tìm thấy instance nào InService trong ASG: $ASG_NAME"
    exit 1
fi

write "## 📦 Available Rollback Versions"
write ""

for INSTANCE_ID in $INSTANCE_IDS; do
    write "### Instance: \`$INSTANCE_ID\`"

    CMD_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"ls -lt /app/releases/${APP_NAME}-* 2>/dev/null | awk '{print \\\$6, \\\$7, \\\$8}' | paste - <(ls -t /app/releases/${APP_NAME}-* 2>/dev/null | sed 's|.*/blog-app-||')\"]" \
        --query 'Command.CommandId' \
        --output text --region "$REGION")

    aws ssm wait command-executed \
        --command-id "$CMD_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" 2>/dev/null || true

    VERSIONS=$(aws ssm get-command-invocation \
        --command-id "$CMD_ID" \
        --instance-id "$INSTANCE_ID" \
        --query 'StandardOutputContent' \
        --output text --region "$REGION" | tr -d '\r')

    if [ -z "$VERSIONS" ]; then
        write "_Không có version nào được lưu trên instance này_"
    else
        write '```'
        write "Date        Time     SHA"
        write "----------- -------- --------"
        write "$VERSIONS"
        write '```'
    fi
    write ""
done

if [ -n "$TARGET_VERSION" ]; then
    write "> ▶️ Sẽ rollback về version: \`$TARGET_VERSION\`"
else
    write "> ℹ️ Chạy lại workflow, điền **version** (SHA 8 ký tự) để rollback."
fi
