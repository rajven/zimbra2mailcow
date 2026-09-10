#!/bin/bash

. /root/mailcow/mailcow_config

[ -z "${1}" ] && exit
[ -z "${2}" ] && exit

ALIAS=${1}
GOTO=${2}

JSON_TMPL='"active": "1", "address": "%ALIAS%", "goto": "%MEMBERS%"'

JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%ALIAS%/${ALIAS}/" | sed "s/%MEMBERS%/${GOTO}/")

echo -n "Create alias ${ALIAS} to ${MEMBERS}: "

STATUS=$(curl -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' -d "{ ${JSON_DATA} }" https://${MC_SERVER}/api/v1/add/alias 2>&1)

[ $? -eq 0 ] && echo "OK" || echo "Fail"

exit
