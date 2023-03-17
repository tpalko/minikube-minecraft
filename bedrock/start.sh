#!/bin/bash 

. /opt/minecraft/scripts/backup.sh

schedule_backup

cd ${HOME}/server

export ENTRIES=(
  activate-cheats=${ACTIVATE_CHEATS}
  allow-cheats=${ALLOW_CHEATS}
  allow-flight=${ALLOW_FLIGHT}
  gamemode=${GAMEMODE}
  keep-inventory=${KEEP_INVENTORY}
  level-name="${WORLD_NAME}"
  server-ip=0.0.0.0
  show-coordinates=${SHOW_COORDINATES}
)

fix_properties
  
echo "Starting server.."
./bedrock_server
