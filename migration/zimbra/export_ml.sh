#!/bin/bash

# ============================================================
# EXPORT ZIMBRA MAILING LISTS
# ============================================================
# Usage: ./export_zimbra_ml.sh
# Run as zimbra user
# ============================================================

# Settings
OUTPUT_DIR="./mailing_lists_export"
REPORT_FILE="lists_report.txt"

# Create export directory
mkdir -p "${OUTPUT_DIR}"

echo "=== Zimbra Mailing Lists Export ==="
echo "Start time: $(date)"

# Get all mailing lists
LISTS=$(zmprov -l gadl)

if [ -z "${LISTS}" ]; then
    echo "❌ No mailing lists found."
    exit 1
fi

echo "Found lists: $(echo "${LISTS}" | wc -l)"

# Clear report file
> "${REPORT_FILE}"

# Safe filename function
safe_filename() {
    echo "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# Process each list
for LIST in ${LISTS}; do
    LIST=$(echo "${LIST}" | tr -d '[:space:]')
    [ -z "${LIST}" ] && continue
    
    echo "Processing: ${LIST}"
    
    # Get list details
    LIST_INFO=$(zmprov -l gdl "${LIST}")
    
    # Extract display name
    LIST_NAME=$(echo "${LIST_INFO}" | grep "^displayName:" | head -1 | cut -d: -f2- | sed 's/^ //')
    if [ -z "${LIST_NAME}" ]; then
        LIST_NAME=$(echo "${LIST}" | cut -d@ -f1)
    fi
    
    # Get members
    MEMBERS=$(zmprov -l gdl "${LIST}" | grep "^zimbraMailForwardingAddress:" | cut -d: -f2- | sed 's/^ //')
    if [ -z "${MEMBERS}" ]; then
        MEMBERS=$(zmprov -l gdl "${LIST}" | grep "^members:" | cut -d: -f2- | sed 's/^ //')
    fi
    
    # Skip empty lists
    if [ -z "${MEMBERS}" ]; then
        echo "  ⚠️ Empty list, skipping"
        continue
    fi
    
    # Save members to file (without timestamp)
    SAFE_NAME=$(safe_filename "${LIST}")
    MEMBERS_FILE="${SAFE_NAME}_members.txt"
    echo "${MEMBERS}" > "${OUTPUT_DIR}/${MEMBERS_FILE}"
    
    # Write to report: full_list_email|relative_path_to_file
    echo "${LIST}|${OUTPUT_DIR}/${MEMBERS_FILE}" >> "${REPORT_FILE}"
    
    echo "  ✅ Saved: ${MEMBERS_FILE}"
done

echo ""
echo "✅ Export completed"
echo "📁 Files: ${OUTPUT_DIR}"
echo "📄 Report: ${REPORT_FILE}"
