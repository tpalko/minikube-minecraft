#!/bin/bash 

. /opt/minecraft/scripts/backup.sh 
echo "Starting backup.."
(while :; do 
  (sleep $(( 60*15 ))) && backup >> /opt/minecraft/log/backup.log 2>&1 || echo "OH NO! something failed in the backup.."
done) &

cd ${HOME}/server

cat server.properties \
  | sed "s/^rcon\.port=.*$/rcon.port=25575/" \
  | sed "s/^rcon\.password=.*$/rcon.password=${RCON_PASSWORD}/" \
  | sed "s/^enable-rcon=.*$/enable-rcon=true/" \
  | sed "s/^activate-cheats=.*$/activate-cheats=${ACTIVATE_CHEATS}/" \
  | sed "s/^allow-cheats=.*$/allow-cheats=${ALLOW_CHEATS}/" \
  | sed "s/^allow-flight=.*$/allow-flight=${ALLOW_FLIGHT}/" \
  | sed "s/^gamemode=.*$/gamemode=${GAMEMODE}/" \
  | sed "s/^keep-inventory=.*$/keep-inventory=${KEEP_INVENTORY}/" \
  | sed "s/^level-name=.*$/level-name=${WORLD_NAME}/" \
  | sed "s/^server-ip=.*$/server-ip=0.0.0.0/" \
  | sed "s/^show-coordinates=.*$/show-coordinates=${SHOW_COORDINATES}/" \
    > server.properties

ENTRIES=(allow-cheats=${ALLOW_CHEATS} activate-cheats=${ACTIVATE_CHEATS} keep-inventory=${KEEP_INVENTORY} show-coordinates=${SHOW_COORDINATES} level-name=${WORLD_NAME})

for ENTRY in ${ENTRIES[@]}; do 
  IFS==; read -ra PARTS <<< "${ENTRY}"
  echo ""
  echo "Looking for ${PARTS[0]} in server.properties.."
  if ! grep "${PARTS[0]}" server.properties 2>&1 >/dev/null; then 
    echo "Adding ${PARTS[0]}=${PARTS[1]} to server.properties"
    printf "${PARTS[0]}=${PARTS[1]}\n" >> server.properties 
  else 
    echo "${PARTS[0]} in server.properties:"
    grep ${PARTS[0]} server.properties
    echo "Fixing ${PARTS[0]}=${PARTS[1]}.."
    sed -i "s/^${parts[0]}=.*$/${PARTS[0]}=${PARTS[1]}/" server.properties 
    echo "${PARTS[0]} in server.properties:"
    grep ${PARTS[0]} server.properties
  fi 
done 

echo "Final server.properties (${PWD}):"

echo "v v v v v v v v"
echo ""
stat server.properties
cat server.properties
echo ""
echo "^ ^ ^ ^ ^ ^ ^ ^"

(sleep 60 && rcon "op ${USERNAME}") &

echo "Starting server.."
java -Djavax.net.ssl.trustStorePassword=changeit -Xmx1024M -Xms1024M -jar server.jar
