#!/bin/bash

. /root/mailcow/mailcow_config

[ -z "${1}" ] && exit

DOMAIN=${1}

ALIAS="for_all@${DOMAIN}"

GOTO=$(/root/mailcow/get_mailboxes.sh ${DOMAIN} | awk '{ s=s","$1 } END { print s }' | sed -r 's/^,//')

ALIAS_ID=$(/root/mailcow/get_aliases.sh | jq ".[] | select(.address==\"${ALIAS}\").id")

[ -z "${ALIAS_ID}" ] && exit
[ -z "${GOTO}" ] && exit

JSON_TMPL='"attr":{"address":"%ALIAS%", "goto": "%MEMBERS%"},"items":["%ALIAS_ID%"]'

JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%ALIAS%/${ALIAS}/" | sed "s/%MEMBERS%/${GOTO}/" | sed "s/%ALIAS_ID%/${ALIAS_ID}/")

echo -n "UDPATE alias ${ALIAS}"

curl -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' -d "{ ${JSON_DATA} }" https://${MC_SERVER}/api/v1/edit/alias 2>&1

exit
