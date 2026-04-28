#!/bin/bash
# Demo backup/restore PostgreSQL - Bài tập 4
# Yêu cầu: docker-compose (postgres) đang chạy tại localhost:5432

set -e

DB_HOST="localhost"
DB_PORT="5432"
DB_USER="admins"
DB_PASS="secretpassword"
DB_NAME="blogdb"
BACKUP_DIR="/tmp/db-backups"
BACKUP_FILE="$BACKUP_DIR/demo_backup_$(date +%Y%m%d_%H%M%S).sql"

export PGPASSWORD="$DB_PASS"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $1"; }
err() { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $1"; }

mkdir -p "$BACKUP_DIR"

# ── BƯỚC 1: Tạo bảng demo và thêm dữ liệu ─────────────────────────────────
log "BƯỚC 1: Tạo bảng demo_products và thêm dữ liệu..."

psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME <<'SQL'
DROP TABLE IF EXISTS demo_products;
CREATE TABLE demo_products (
    id      SERIAL PRIMARY KEY,
    name    VARCHAR(100) NOT NULL,
    price   NUMERIC(10,2),
    stock   INT,
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO demo_products (name, price, stock) VALUES
    ('Laptop Dell XPS 15',    35000000, 10),
    ('iPhone 15 Pro',         27000000, 25),
    ('Samsung Galaxy S24',    22000000, 30),
    ('AirPods Pro 2',          6500000, 50),
    ('MacBook Air M3',        30000000,  8),
    ('Sony WH-1000XM5',       9000000, 15),
    ('iPad Pro 12.9',         25000000, 12),
    ('Logitech MX Master 3',   2500000, 40);
SQL

echo ""
log "Dữ liệu ban đầu (8 sản phẩm):"
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME \
    -c "SELECT id, name, price, stock FROM demo_products ORDER BY id;"

# ── BƯỚC 2: Backup bằng pg_dump ───────────────────────────────────────────
log "BƯỚC 2: Thực hiện backup với pg_dump..."

pg_dump -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME \
    --table=demo_products \
    --format=plain \
    --file="$BACKUP_FILE"

BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
log "Backup hoàn thành: $BACKUP_FILE ($BACKUP_SIZE)"

# ── BƯỚC 3: Mô phỏng sự cố - xóa một phần dữ liệu ─────────────────────────
warn "BƯỚC 3: Mô phỏng sự cố - xóa sản phẩm có id <= 4..."

psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME \
    -c "DELETE FROM demo_products WHERE id <= 4;"

echo ""
warn "Dữ liệu sau khi xóa (chỉ còn 4 sản phẩm):"
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME \
    -c "SELECT id, name, price, stock FROM demo_products ORDER BY id;"

# ── BƯỚC 4: Restore từ backup ─────────────────────────────────────────────
log "BƯỚC 4: Restore từ backup..."

# Drop và tạo lại bảng trống trước khi restore
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME \
    -c "DROP TABLE IF EXISTS demo_products;"

psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME < "$BACKUP_FILE"

log "Restore hoàn thành."

# ── BƯỚC 5: Kiểm tra dữ liệu sau restore ─────────────────────────────────
log "BƯỚC 5: Kiểm tra dữ liệu sau restore:"
echo ""

COUNT=$(psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME \
    -t -c "SELECT COUNT(*) FROM demo_products;" | tr -d ' ')

psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME \
    -c "SELECT id, name, price, stock FROM demo_products ORDER BY id;"

echo ""
if [ "$COUNT" -eq 8 ]; then
    log "RESTORE THÀNH CÔNG — Phục hồi đủ $COUNT/8 sản phẩm."
else
    err "CẢNH BÁO — Chỉ phục hồi được $COUNT/8 sản phẩm."
fi

log "Backup file lưu tại: $BACKUP_FILE"
