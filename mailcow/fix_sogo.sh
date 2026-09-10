#!/bin/bash

DOCKER_CMD="/usr/bin/docker compose exec "

cd /opt/mailcow-dockerized

${DOCKER_CMD} -T dovecot-mailcow doveadm mailbox list -A INBOX | grep -v mailcow.local | awk '{ print $1 }' | while read EMAIL; do

echo "SET SOGO for: ${EMAIL}"

##SOGO_CMD=$(${DOCKER_CMD} -d -u sogo -it sogo-mailcow /usr/sbin/sogo-tool user-preferences set defaults ${EMAIL} SOGoRefreshViewCheck '{"SOGoRefreshViewCheck":"every_minute"}')
#SOGO_CMD=$(${DOCKER_CMD} -d -u sogo -it sogo-mailcow /usr/sbin/sogo-tool user-preferences set defaults ${EMAIL} SOGoAnimationMode '{"SOGoAnimationMode":"limited"}')
##SOGO_CMD=$(${DOCKER_CMD} -d -u sogo -it sogo-mailcow /usr/sbin/sogo-tool user-preferences set defaults ${EMAIL} SOGoAnimationMode '{"SOGoAnimationMode":"none"}')
##SOGO_CMD=$(${DOCKER_CMD} -d -u sogo -it sogo-mailcow /usr/sbin/sogo-tool user-preferences set defaults ${EMAIL} SOGoMailComposeMessageType '{"SOGoMailComposeMessageType":"html"}')
#SOGO_CMD=$(${DOCKER_CMD} -d -u sogo -it sogo-mailcow /usr/sbin/sogo-tool user-preferences set defaults ${EMAIL} SOGoMailDisplayFullEmail '{"SOGoMailDisplayFullEmail":"1"}')
SOGO_CMD=$(${DOCKER_CMD} -d -u sogo -it sogo-mailcow /usr/sbin/sogo-tool user-preferences set defaults ${EMAIL} SOGoMailHideInlineAttachments '{"SOGoMailHideInlineAttachments":"1"}')

done

exit
