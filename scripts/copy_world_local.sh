#!/bin/bash 

if [[ ! -d ./backups ]]; then 
  echo "Please run from the project root (minecraft/)"
  exit 1
fi 

CONTAINER_ID=$(docker ps --filter="name=minecraft-server")

if [[ -z "${CONTAINER_ID}" ]]; then 
  echo "minecraft-server doesn't appear to be a container here"
  exit 1
fi 

TARGET_FOLDER=backups/$(date +%Y%m%dT%H%M%S)/server/
mkdir -p ${TARGET_FOLDER}
docker cp $(docker ps --filter="name=minecraft-server" -q):/opt/minecraft/server/world ${TARGET_FOLDER}
