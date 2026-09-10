#!/bin/bash

exit

DOCKER_CMD="/usr/bin/docker compose exec "

cd /opt/mailcow-dockerized


function clear_mailbox {
MBOX=${1}
FOLDER=${2}
FILTER=${3}
[ -z "${MBOX}" ] && return 1
[ -z "${FOLDER}" ] && FOLDER="Junk"
[ -z "${FILTER}" ] && FILTER="savedbefore 1w"
${DOCKER_CMD} -d -it dovecot-mailcow doveadm expunge -u ${MBOX} mailbox "${FOLDER}" from 'wordpress@example.com'
}

function clear_mailboxes {
FOLDER=${1}
FILTER=${2}
[ -z "${FOLDER}" ] && FOLDER="Junk"
[ -z "${FILTER}" ] && FILTER="savedbefore 1w"
${DOCKER_CMD} dovecot-mailcow doveadm mailbox list -A | egrep "${FOLDER}\s*$" | awk '{ print $1 }' | while read EMAIL; do
    [ -z "${EMAIL}" ] && continue
    echo -n "Clear ${FOLDER} for ${EMAIL} with ${FILTER}"
    clear_mailbox "${EMAIL}" "${FOLDER}" "${FILTER}"
    [ $? -eq 0 ] && echo " Done!" || echo " Fail!"
done
}

#Delete mails
clear_mailboxes 'INBOX'

exit
