#!/bin/bash

set -e 

# -- WORLD_NAME originates from an .env file which must double-quote values with spaces 
# -- in the pod, .env is represented by a ConfigMap, which again wraps values in double quotes
# -- and so the original double quotes become part of the value, not functional encapsulating syntax 
export WORLD_NAME=$(echo ${WORLD_NAME} | sed "s/\"//g")

BACKUPS_WORLD_FOLDER="/opt/minecraft/backups/${WORLD_NAME}"
echo "Creating ${BACKUPS_WORLD_FOLDER}.."
mkdir -p "${BACKUPS_WORLD_FOLDER}"

function rcon {
  if [[ -f /opt/minecraft/tools/mcrcon/mcrcon ]]; then 
    CMD=$1
    /opt/minecraft/tools/mcrcon/mcrcon -H 127.0.0.1 -P 25575 -p ${RCON_PASSWORD} "${CMD}"
  else 
    echo "no mcrcon"
  fi 
}

function backup() {
  echo "--------------------------------"
  echo "-- BACKUP $(date +%F-%H-%M) ----"
  echo "--"

  rcon "save-off"
  rcon "save-all"
  tar -cvpzf "${BACKUPS_WORLD_FOLDER}/${WORLD_NAME}-world-${VERSION}-$(date +%F-%H-%M).tar.gz" "${WORLD_BASE}/${WORLD_NAME}"
  rcon "save-on"

  echo "Deleting older backups.."
  for OLD in $(find ${BACKUPS_WORLD_FOLDER} -type f -mtime +3 -name '*.gz'); do 
    rm -v ${OLD}
  done 

  echo "--"
  echo "-- BACKUP END $(date +%F-%H-%M) ----"
  echo "--------------------------------"
}


echo "rcon and backup sourced"
