#!/bin/bash

# ============================================================
# ENABLE BLOCKED MAILCOW USERS
# ============================================================
# Usage: ./enable_mailcow_users.sh mailcow_full_20260909.csv
# ============================================================

# Load mailcow config
. /root/mailcow/mailcow_config

CSV_FILE="${1}"
if [ -z "${CSV_FILE}" ] || [ ! -f "${CSV_FILE}" ]; then
    echo "❌ Error: specify CSV file"
    echo "Usage: $0 mailcow_full_20260909.csv"
    exit 1
fi

LOG_FILE="/root/mailcow/enable_users_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log "🚀 ENABLING USERS FROM: ${CSV_FILE}"

TOTAL=0
ENABLED=0
FAILED=0

# Skip header, read CSV
tail -n +2 "${CSV_FILE}" | while IFS='|' read -r email password displayName aliases quota active attributes; do
    [ -z "${email}" ] && continue

    TOTAL=$((TOTAL + 1))

    # Only process blocked users (active=0)
    if [ "${active}" != "0" ]; then
        continue
    fi

    log "---------- [${TOTAL}] Enabling: ${email} ----------"

    JSON_TMPL='"attr":{"active":"1","sogo_access":"1"},"items":["%EMAIL%"]'
    JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%EMAIL%/${email}/")

    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" "https://${MC_SERVER}/api/v1/edit/mailbox" 2>&1)

    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        log "  ✅ Enabled"
        ENABLED=$((ENABLED + 1))
    else
        log "  ❌ Failed: ${RESULT}"
        FAILED=$((FAILED + 1))
    fi

    sleep 0.3
done

log ""
log "=========================================="
log "✅ DONE"
log "Enabled: ${ENABLED}"
log "Failed: ${FAILED}"
log "Log: ${LOG_FILE}"
log "=========================================="
