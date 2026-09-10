#!/bin/bash

. /root/mailcow/mailcow_config

[ -z "${1}" ] && exit

DOMAIN=${1}

[ -z "${DOMAIN}" ] && DOMAIN="mailcow.local"

curl -s  -X 'GET' -H "X-API-Key: ${API_RO_KEY}" -H 'Content-Type: application/json' https://${MC_SERVER}//api/v1/get/mailbox/all/${DOMAIN} |  jq '.[] | select(.active==1).username' | sed 's/\"//g'

exit
