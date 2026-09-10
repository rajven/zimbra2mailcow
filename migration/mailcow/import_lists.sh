#!/bin/bash

# ============================================================
# IMPORT ZIMBRA MAILING LISTS TO MAILCOW (AS ALIASES)
# ============================================================
# Usage: ./import_lists.sh
# Reads lists_report.txt from current directory
# Format: list_email|/path/to/members_file.txt
# ============================================================

# Load mailcow config
. /root/mailcow/mailcow_config

# Check for report file
REPORT_FILE="./lists_report.txt"
if [ ! -f "${REPORT_FILE}" ]; then
    echo "❌ Error: ${REPORT_FILE} not found in current directory"
    exit 1
fi

# Create log directories
LOG_DIR="/root/mailcow/import_lists_logs"
mkdir -p ${LOG_DIR}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/import_lists_${TIMESTAMP}.log"
ERROR_FILE="${LOG_DIR}/errors_${TIMESTAMP}.log"
SUCCESS_FILE="${LOG_DIR}/success_${TIMESTAMP}.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

log "🚀 STARTING MAILING LISTS IMPORT"
log "📁 Report file: ${REPORT_FILE}"
log "📝 Log: ${LOG_FILE}"

# Counters
TOTAL=0
CREATED=0
UPDATED=0
FAILED=0

# ============================================================
# FUNCTION TO CREATE/UPDATE ALIAS (MAILING LIST)
# ============================================================
create_alias() {
    local ALIAS_EMAIL="${1}"
    local MEMBERS_FILE="${2}"
    
    # Extract domain
    DOMAIN=$(echo "${ALIAS_EMAIL}" | awk -F "@" '{ print $NF }')
    
    # Read members from file - one per line, convert to comma-separated
    GOTO=$(cat "${MEMBERS_FILE}" | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
    
    if [ -z "${GOTO}" ]; then
        log "⚠️ Alias ${ALIAS_EMAIL} has no members, skipping"
        return 0
    fi
    
    # Check if alias exists
    ALIAS_ID=$(curl -s -X 'GET' -H "X-API-Key: ${API_RO_KEY}" -H 'Content-Type: application/json' \
        "https://${MC_SERVER}/api/v1/get/alias/all" | jq -r ".[] | select(.address==\"${ALIAS_EMAIL}\").id" 2>/dev/null)
    
    if [ ! -z "${ALIAS_ID}" ] && [ "${ALIAS_ID}" != "null" ]; then
        log "⚠️ Alias ${ALIAS_EMAIL} already exists, updating..."
        update_alias "${ALIAS_EMAIL}" "${GOTO}" "${ALIAS_ID}"
        return $?
    fi
    
    # Create new alias
    JSON_TMPL='"active": "1", "address": "%ALIAS%", "goto": "%GOTO%"'
    JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%ALIAS%/${ALIAS_EMAIL}/" | sed "s/%GOTO%/${GOTO}/")
    
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" "https://${MC_SERVER}/api/v1/add/alias" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        MEMBERS_COUNT=$(echo "${GOTO}" | tr ',' '\n' | wc -l)
        log "✅ Created alias: ${ALIAS_EMAIL} -> ${MEMBERS_COUNT} members"
        echo "${ALIAS_EMAIL}" >> ${SUCCESS_FILE}
        return 0
    else
        log "❌ Error creating alias ${ALIAS_EMAIL}: ${RESULT}"
        echo "${ALIAS_EMAIL}|${RESULT}" >> ${ERROR_FILE}
        return 1
    fi
}

# ============================================================
# FUNCTION TO UPDATE ALIAS
# ============================================================
update_alias() {
    local ALIAS_EMAIL="${1}"
    local GOTO="${2}"
    local ALIAS_ID="${3}"
    
    # Check current goto
    CURRENT_GOTO=$(curl -s -X 'GET' -H "X-API-Key: ${API_RO_KEY}" -H 'Content-Type: application/json' \
        "https://${MC_SERVER}/api/v1/get/alias/all" | jq -r ".[] | select(.address==\"${ALIAS_EMAIL}\").goto" 2>/dev/null)
    
    # Skip if same
    if [ "${CURRENT_GOTO}" = "${GOTO}" ]; then
        log "⏭️ Alias ${ALIAS_EMAIL} already up to date"
        return 0
    fi
    
    # Update alias
    JSON_TMPL='"attr":{"active":"1","goto":"%GOTO%"},"items":["%ALIAS_ID%"]'
    JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%GOTO%/${GOTO}/" | sed "s/%ALIAS_ID%/${ALIAS_ID}/")
    
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" "https://${MC_SERVER}/api/v1/edit/alias" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        MEMBERS_COUNT=$(echo "${GOTO}" | tr ',' '\n' | wc -l)
        log "🔄 Updated alias: ${ALIAS_EMAIL} -> ${MEMBERS_COUNT} members"
        UPDATED=$((UPDATED + 1))
        return 0
    else
        log "❌ Error updating alias ${ALIAS_EMAIL}: ${RESULT}"
        echo "${ALIAS_EMAIL}|${RESULT}" >> ${ERROR_FILE}
        return 1
    fi
}

# ============================================================
# MAIN IMPORT LOGIC
# ============================================================
log "📊 Processing report file..."

# Read report file: list_email|path_to_members_file
while IFS='|' read -r ALIAS_EMAIL MEMBERS_FILE; do
    # Skip empty lines
    [ -z "${ALIAS_EMAIL}" ] && continue
    
    TOTAL=$((TOTAL + 1))
    
    log ""
    log "---------- [${TOTAL}] Processing: ${ALIAS_EMAIL} ----------"
    
    # Check if members file exists
    if [ ! -f "${MEMBERS_FILE}" ]; then
        log "❌ Members file not found: ${MEMBERS_FILE}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Create or update alias
    if create_alias "${ALIAS_EMAIL}" "${MEMBERS_FILE}"; then
        CREATED=$((CREATED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
    
    # Small delay to avoid API overload
    sleep 0.5
    
done < "${REPORT_FILE}"

# ============================================================
# FINAL REPORT
# ============================================================
log ""
log "=========================================="
log "✅ MAILING LISTS IMPORT COMPLETED"
log "=========================================="
log "📊 Total processed: ${TOTAL}"
log "✅ Created: ${CREATED}"
log "🔄 Updated: ${UPDATED}"
log "❌ Failed: ${FAILED}"
log ""
log "📁 Log: ${LOG_FILE}"
log "❌ Errors: ${ERROR_FILE}"
log "✅ Success: ${SUCCESS_FILE}"
log "=========================================="

exit 0
