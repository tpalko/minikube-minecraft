#!/bin/bash 

if [[ $# -lt 1 ]]; then 
  echo "Usage: $0 up|down"
  exit 1
fi 

ACTION=$1 
CRONTAB_TITLE="${IMAGE} container world volume backup"

. .env

# -- remove cron 
crontab -l | awk "/${CRONTAB_TITLE}/{c=2;next} !(c&&c--)" | crontab -

if [[ "${ACTION}" == "up" ]]; then 

  docker-compose up --build --force-recreate -d $@

  # -- add cron 
  printf "$(crontab -l)\n# ${CRONTAB_TITLE}\n*/15 * * * * cp -anv \"live/backups/${WORLD_NAME}/*\" \"${PWD}/backups/${WORLD_NAME}/\"\n" | crontab -

else 
  
  docker-compose down 
  cp -anv "live/backups/${WORLD_NAME}/*" "${PWD}/backups/${WORLD_NAME}/"

fi 
