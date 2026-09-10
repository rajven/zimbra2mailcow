#!/bin/bash

OUTPUT="mailcow_full_$(date +%Y%m%d).csv"
PASSWORDS_FILE="mailcow_passwords_$(date +%Y%m%d).txt"

echo "email|password|displayName|aliases|quota|active|attributes" > $OUTPUT

echo "====== NEW PASSWORD ======" > $PASSWORDS_FILE

for ACCOUNT in $(zmprov -l gaa); do
    DISPLAY_NAME=$(zmprov ga $ACCOUNT displayName | grep "^displayName:" | awk -F': ' '{print $2}' | head -1)
    ALIASES=$(zmprov ga $ACCOUNT zimbraMailAlias | grep "^zimbraMailAlias:" | awk -F': ' '{print $2}' | paste -sd ",")
    STATUS=$(zmprov ga $ACCOUNT zimbraAccountStatus | grep "^zimbraAccountStatus:" | awk -F': ' '{print $2}')
    PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
    QUOTA_MB="90000"
    case "$STATUS" in
        "active") ACTIVE="1" ;;
        "maintenance"|"locked"|"closed") ACTIVE="0" ;;
        *) ACTIVE="1" ;;
    esac
    [ -z "$DISPLAY_NAME" ] && DISPLAY_NAME="$ACCOUNT"
    [ -z "$ALIASES" ] && ALIASES=""
    echo "$ACCOUNT|$PASSWORD|$DISPLAY_NAME|$ALIASES|$QUOTA_MB|$ACTIVE|" >> $OUTPUT
    echo "$ACCOUNT => $PASSWORD" >> $PASSWORDS_FILE
done
