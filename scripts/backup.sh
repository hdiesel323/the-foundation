#!/bin/bash
# /opt/openclaw/scripts/backup.sh
set -euo pipefail

BACKUP_DIR="/opt/openclaw/backups"
R2_BUCKET="openclaw-backups"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="openclaw_${TIMESTAMP}.sql.gz.gpg"

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

# Create backup
docker exec openclaw-postgres pg_dump -U openclaw openclaw | \
    gzip | \
    gpg --symmetric --cipher-algo AES256 --batch --yes \
        --passphrase-file /opt/openclaw/secrets/backup_passphrase.txt > \
    "${BACKUP_DIR}/${BACKUP_FILE}"

# Upload to R2 (if configured)
if [ -n "${CF_ACCOUNT_ID:-}" ]; then
    aws s3 cp "${BACKUP_DIR}/${BACKUP_FILE}" "s3://${R2_BUCKET}/${BACKUP_FILE}" \
        --endpoint-url "https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com"
fi

# Cleanup old local backups
find "${BACKUP_DIR}" -name "openclaw_*.sql.gz.gpg" -mtime +${RETENTION_DAYS} -delete

echo "Backup completed: ${BACKUP_FILE}"
