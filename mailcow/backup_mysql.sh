#!/bin/bash

cd /opt/mailcow-dockerized
source mailcow.conf
DATE=$(date +"%Y%m%d_%H%M%S")
docker compose exec -T mysql-mailcow mysqldump --extended-insert=FALSE --default-character-set=utf8mb4 -u${DBUSER} -p${DBPASS} ${DBNAME} > backup_${DBNAME}_${DATE}.sql
