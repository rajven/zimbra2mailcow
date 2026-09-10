#!/bin/bash

DOCKER_CMD="/usr/bin/docker compose exec "

cd /opt/mailcow-dockerized


function clear_mailbox {
MBOX=${1}
FOLDER=${2}
FILTER=${3}
[ -z "${MBOX}" ] && return 1
[ -z "${FOLDER}" ] && FOLDER="Junk"
[ -z "${FILTER}" ] && FILTER="savedbefore 1w"
${DOCKER_CMD} -d -it dovecot-mailcow doveadm expunge -u ${MBOX} mailbox "${FOLDER}" $FILTER
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

# Delete mails older than 1 wheek
clear_mailboxes 'Nagios/any' 'savedbefore 1w'
clear_mailboxes 'Nagios/switches' 'savedbefore 1w'
clear_mailboxes 'Nagios/Power' 'savedbefore 1w'
clear_mailboxes 'Nagios/servers' 'savedbefore 1w'
clear_mailboxes 'Nagios/voip' 'savedbefore 1w'
clear_mailboxes 'Nagios/netping' 'savedbefore 1w'
clear_mailboxes 'Nagios/syslog' 'savedbefore 1w'
clear_mailboxes 'Nagios/Temperature' 'savedbefore 1w'
clear_mailboxes 'Logs' 'savedbefore 1w'
clear_mailboxes 'Voice' 'savedbefore 1w'

#Delete mails older than 3 days
clear_mailboxes 'Billing' 'savedbefore 3d'
clear_mailboxes 'Cron' 'savedbefore 3d'

# Delete mails from junk which are read and older than 12 hours
${DOCKER_CMD} dovecot-mailcow doveadm expunge -A mailbox 'Junk' SEEN not SINCE 12h

# Delete mails from junk which are NOT read and older than 3 wheek
${DOCKER_CMD} dovecot-mailcow doveadm expunge -A mailbox 'Junk' not SEEN savedbefore 3w

exit
