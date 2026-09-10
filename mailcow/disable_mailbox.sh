#!/bin/bash

. /root/mailcow/mailcow_config

[ -z "${1}" ] && exit

MAILBOX=${1}

JSON_TMPL='"attr":{"active":"0","sogo_access":"0"},"items":["%MBOX%"]'

JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%MBOX%/${MAILBOX}/")

echo -n "Disable ${MAILBOX}"

STATUS=$(curl -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' -d "{ ${JSON_DATA} }" https://${MC_SERVER}/api/v1/edit/mailbox)

[ $? -eq 0 ] && echo "OK" || echo "Fail"

exit
