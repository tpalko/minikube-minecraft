#!/bin/bash 

. /opt/minecraft/scripts/backup.sh

schedule_backup

cd ${HOME}/server

export ENTRIES=(
  rcon.port=25575
  rcon.password=${RCON_PASSWORD}
  enable-rcon=true
  activate-cheats=${ACTIVATE_CHEATS}
  allow-cheats=${ALLOW_CHEATS}
  allow-flight=${ALLOW_FLIGHT}
  gamemode=${GAMEMODE}
  motd=${MOTD}
  keep-inventory=${KEEP_INVENTORY}
  level-name=${WORLD_NAME}
  server-ip=0.0.0.0
  show-coordinates=${SHOW_COORDINATES}
  enforce-secure-profile=${ENFORCE_SECURE_PROFILE}
)

fix_properties

(sleep 60 && rcon "op ${USERNAME}") &

echo "Where is log4j2*.xml?"
find . -name "log4j2*.xml"

echo "Starting server.."
# JAVA_CMD="java -cp \"./*:./patch/*\" ${JAVA_CONF} -Djavax.net.ssl.trustStorePassword=changeit -Xmx1024M -Xms1024M -jar server.jar"
java -cp "./*:./patch/*" ${JAVA_CONF} -Djavax.net.ssl.trustStorePassword=changeit -Xmx1024M -Xms1024M -jar server.jar
# echo ${JAVA_CMD}
# ${JAVA_CMD}
