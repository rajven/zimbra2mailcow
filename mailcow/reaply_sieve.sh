#!/bin/bash

EMAIL=$1

[ -z "${EMAIL}" ] && exit

LOGIN=$(echo "${EMAIL}" | awk -F "@" '{ print $1 }')
DOMAIN=$(echo "${EMAIL}" | awk -F "@" '{ print $2 }')

DOCKER_CMD="/usr/bin/docker compose exec dovecot-mailcow"

cd /opt/mailcow-dockerized

echo "${DOCKER_CMD} /usr/bin/sieve-filter -u ${EMAIL} /var/vmail/${DOMAIN}/${LOGIN}/sieve/sogo.sieve INBOX"

#${DOCKER_CMD} /usr/bin/sieve-filter -u ${EMAIL} /var/vmail/${DOMAIN}/${LOGIN}/sieve/sogo.sieve INBOX

exit
