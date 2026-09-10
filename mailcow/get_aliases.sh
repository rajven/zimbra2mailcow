#!/bin/bash

. /root/mailcow/mailcow_config

curl -s -X 'GET' -H "X-API-Key: ${API_RO_KEY}" -H 'Content-Type: application/json' https://${MC_SERVER}//api/v1/get/alias/all

exit
