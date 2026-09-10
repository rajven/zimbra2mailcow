#!/bin/bash

DOCKER_CMD="/usr/bin/docker compose exec dovecot-mailcow"

cd /opt/mailcow-dockerized

${DOCKER_CMD} doveadm expunge -A mailbox 'Junk' all

exit
