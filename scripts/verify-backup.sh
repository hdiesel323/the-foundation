#!/bin/bash
# /opt/openclaw/scripts/verify-backup.sh
# Weekly backup verification — tests that the latest backup can be decrypted and decompressed
# without restoring to production. Scheduled via cron: 0 4 * * 0
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/openclaw/backups}"
PASSPHRASE_FILE="/opt/openclaw/secrets/backup_passphrase.txt"

# Find the latest backup file
LATEST_BACKUP=$(ls -t "${BACKUP_DIR}"/openclaw_*.sql.gz.gpg 2>/dev/null | head -1)

if [ -z "${LATEST_BACKUP}" ]; then
    echo "FAIL: No backup files found in ${BACKUP_DIR}"
    exit 1
fi

echo "Verifying backup: ${LATEST_BACKUP}"
echo "File size: $(du -h "${LATEST_BACKUP}" | cut -f1)"

# Test decryption and decompression without restoring
# Pipeline: gpg decrypt -> gunzip -> count lines (piped to wc, not to psql)
LINE_COUNT=$(gpg --decrypt --batch --yes --passphrase-file "${PASSPHRASE_FILE}" \
    "${LATEST_BACKUP}" 2>/dev/null | \
    gunzip | \
    wc -l)

if [ "${LINE_COUNT}" -gt 0 ]; then
    echo "OK: Backup verified — ${LINE_COUNT} SQL lines recovered"
    echo "Backup file: $(basename "${LATEST_BACKUP}")"
    echo "Verified at: $(date -Iseconds)"
    exit 0
else
    echo "FAIL: Backup decrypted but contains 0 lines"
    exit 1
fi
