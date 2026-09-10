#!/bin/bash

DOCKER_CMD="/usr/bin/docker compose exec dovecot-mailcow"

cd /opt/mailcow-dockerized

# Delete mails from junk which are read and older than 12 hours
${DOCKER_CMD} doveadm expunge -A mailbox 'Junk' SEEN not SINCE 12h

# Delete mails from junk which are NOT read and older than 3 wheek
${DOCKER_CMD} doveadm expunge -A mailbox 'Junk' not SEEN savedbefore 3w

exit
