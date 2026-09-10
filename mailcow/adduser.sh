#!/bin/bash

. /root/mailcow/mailcow_config

[ -z "${1}" ] && exit
[ -z "${2}" ] && exit

MAILBOX=${1}
FIO=${2}
PASSWORD=${3}

DOMAIN=$(echo "${MAILBOX}" | awk -F "@" '{ print $NF }')
LOCAL_PART=$(echo "${MAILBOX}" | awk -F "@" '{ print $1 }')

if [ -z "${DOMAIN}" ]; then
    echo "Need domain name for mailbox!"
    exit 100
    fi
if [ -z "${3}" ]; then
    PASSWORD=$(pwgen 12 1)
    fi

JSON_TMPL='"active": "1", "domain": "%DOMAIN%", "local_part": "%MBOX%", "name": "%FIO%", "password": "%PASS%", "password2": "%PASS%","quota": "1024", "force_pw_update": "0", "tls_enforce_in": "1", "tls_enforce_out": "1"'

JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%DOMAIN%/${DOMAIN}/" | sed "s/%MBOX%/${LOCAL_PART}/" | sed "s/%PASS%/${PASSWORD}/g" | sed "s/%FIO%/${FIO}/")

echo -n "Create ${LOCAL_PART}@${DOMAIN}; ${PASSWORD}; ${FIO}: "

STATUS=$(curl -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' -d "{ ${JSON_DATA} }" https://${MC_SERVER}/api/v1/add/mailbox 2>&1)

[ $? -eq 0 ] && echo "OK" || echo "Fail"

exit
