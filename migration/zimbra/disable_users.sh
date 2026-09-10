#!/bin/bash

# ============================================================
# DISABLE ZIMBRA USERS
# ============================================================
# Usage: ./disable_users.sh mailcow_full_20260909.csv
# Run as zimbra user
# ============================================================

CSV_FILE="${1}"
if [ -z "${CSV_FILE}" ] || [ ! -f "${CSV_FILE}" ]; then
    echo "❌ Error: specify CSV file"
    echo "Usage: $0 mailcow_full_20260909.csv"
    exit 1
fi

LOG_FILE="disable_users_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log "🚀 DISABLING USERS FROM: ${CSV_FILE}"

TOTAL=0
DISABLED=0
FAILED=0

# Skip header, read CSV
tail -n +2 "${CSV_FILE}" | while IFS='|' read -r email password displayName aliases quota active attributes; do
    [ -z "${email}" ] && continue
    
    TOTAL=$((TOTAL + 1))
    
    # Only process blocked users (active=0) - same as enabled by script 1
    if [ "${active}" != "0" ]; then
        continue
    fi
    
    log "---------- [${TOTAL}] Disabling: ${email} ----------"
    
    # Lock account
    RESULT=$(zmprov ma "${email}" zimbraAccountStatus locked 2>&1)
    if [ $? -ne 0 ]; then
        log "❌ Failed to disable ${email}: ${RESULT}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    log "  ✅ Account disabled"
    DISABLED=$((DISABLED + 1))
done

log ""
log "=========================================="
log "✅ DONE"
log "Total: ${TOTAL}"
log "Disabled: ${DISABLED}"
log "Failed: ${FAILED}"
log "Log: ${LOG_FILE}"
log "=========================================="
