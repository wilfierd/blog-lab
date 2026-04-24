#!/bin/bash
# Tự động cập nhật Prometheus targets khi ASG scale in/out
# Chạy: ./sync-targets.sh
# Cron (mỗi 2 phút): */2 * * * * /path/to/sync-targets.sh >> /var/log/sync-targets.log 2>&1

set -euo pipefail

REGION="us-west-2"
ASG_NAME="blog-app-asg"
PROM_TEMPLATE="$(dirname "$0")/prometheus.yml.template"
PROM_CONFIG="$(dirname "$0")/prometheus.yml"
ENV_FILE="$(dirname "$0")/../.env"
PROM_URL="http://localhost:9090/-/reload"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Load AWS credentials từ .env
if [[ -f "$ENV_FILE" ]]; then
  export $(grep -E '^AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY|REGION)' "$ENV_FILE" | xargs)
fi

log "Fetching active instances in ASG: $ASG_NAME"

# Lấy danh sách instance InService
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region "$REGION" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
  --output text)

if [[ -z "$INSTANCE_IDS" ]]; then
  log "ERROR: No InService instances found"
  exit 1
fi

log "Instances: $INSTANCE_IDS"

# Lấy Tailscale IP từng instance qua SSM
TAILSCALE_IPS=()
for INST in $INSTANCE_IDS; do
  CMD_ID=$(aws ssm send-command \
    --instance-id "$INST" \
    --document-name "AWS-RunShellScript" \
    --region "$REGION" \
    --parameters 'commands=["tailscale ip -4 2>/dev/null || echo no-tailscale"]' \
    --query 'Command.CommandId' --output text 2>/dev/null)

  sleep 4

  IP=$(aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$INST" \
    --region "$REGION" \
    --query 'StandardOutputContent' --output text 2>/dev/null | tr -d '[:space:]')

  if [[ "$IP" == "no-tailscale" || -z "$IP" ]]; then
    log "WARN: $INST has no Tailscale, skipping"
    continue
  fi

  log "$INST -> Tailscale IP: $IP"
  TAILSCALE_IPS+=("$IP")
done

if [[ ${#TAILSCALE_IPS[@]} -eq 0 ]]; then
  log "ERROR: No instances have Tailscale. Run install-tailscale.sh first."
  exit 1
fi

# Build targets list cho prometheus (dùng IP đầu tiên cho EC2_1, thứ hai cho EC2_2...)
EC2_1_IP="${TAILSCALE_IPS[0]}"
EC2_2_IP="${TAILSCALE_IPS[1]:-${TAILSCALE_IPS[0]}}"  # fallback về IP đầu nếu chỉ có 1

log "Updating prometheus.yml: EC2_1=$EC2_1_IP EC2_2=$EC2_2_IP"

# Build scrape targets từ tất cả IPs
BLOG_TARGETS=$(printf "'%s:8080', " "${TAILSCALE_IPS[@]}" | sed 's/, $//')
NODE_TARGETS=$(printf "'%s:9100', " "${TAILSCALE_IPS[@]}" | sed 's/, $//')

# Render prometheus.yml từ template
EC2_1_TAILSCALE_IP="$EC2_1_IP" envsubst < "$PROM_TEMPLATE" > "$PROM_CONFIG.tmp"

# Thay static targets bằng multi-target nếu có nhiều hơn 1 instance
sed -i "s|targets: \['${EC2_1_IP}:8080'\]|targets: [${BLOG_TARGETS}]|g" "$PROM_CONFIG.tmp"
sed -i "s|targets: \['${EC2_1_IP}:9100'\]|targets: [${NODE_TARGETS}]|g" "$PROM_CONFIG.tmp"

# Chỉ update nếu thực sự thay đổi
if diff -q "$PROM_CONFIG.tmp" "$PROM_CONFIG" > /dev/null 2>&1; then
  log "No changes needed"
  rm "$PROM_CONFIG.tmp"
  exit 0
fi

mv "$PROM_CONFIG.tmp" "$PROM_CONFIG"
log "prometheus.yml updated"

# Update .env với IPs mới
if [[ -f "$ENV_FILE" ]]; then
  sed -i "s|^EC2_1_TAILSCALE_IP=.*|EC2_1_TAILSCALE_IP=${TAILSCALE_IPS[0]}|" "$ENV_FILE"
  [[ ${#TAILSCALE_IPS[@]} -ge 2 ]] && \
    sed -i "s|^EC2_2_TAILSCALE_IP=.*|EC2_2_TAILSCALE_IP=${TAILSCALE_IPS[1]}|" "$ENV_FILE"
fi

# Reload Prometheus (không restart, giữ nguyên data)
if curl -s -X POST "$PROM_URL" > /dev/null 2>&1; then
  log "Prometheus reloaded"
else
  log "WARN: Prometheus reload failed (container down?)"
fi

log "Done. Active targets: ${TAILSCALE_IPS[*]}"
