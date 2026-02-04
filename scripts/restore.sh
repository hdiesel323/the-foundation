#!/bin/bash
# /opt/openclaw/scripts/restore.sh
set -euo pipefail

BACKUP_FILE="${1:?Usage: restore.sh <backup_file.sql.gz.gpg>}"

echo "Restoring from: ${BACKUP_FILE}"

gpg --decrypt --batch --yes --passphrase-file /opt/openclaw/secrets/backup_passphrase.txt \
    "${BACKUP_FILE}" | \
    gunzip | \
    docker exec -i openclaw-postgres psql -U openclaw -d openclaw

echo "Restore completed."
