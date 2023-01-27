#!/bin/bash

set -e 

env | grep -E "^MINECRAFT_"

if [[ -n "${MINECRAFT_PROXY_BEDROCK_UPSTREAM_HOST}" ]]; then 
  (envsubst < /app/nginx-bedrock-tcp.conf.tmpl > /app/nginx-bedrock-tcp.conf \
    && envsubst < /app/nginx-bedrock-udp.conf.tmpl > /app/nginx-bedrock-udp.conf \
    && echo "$(cat /app/nginx-bedrock-tcp.conf)" \
    && echo "$(cat /app/nginx-bedrock-udp.conf)" \
    && echo "running bedrock nginxes.." \
    && nginx -c /app/nginx-bedrock-tcp.conf -g "daemon on;" \
    && nginx -c /app/nginx-bedrock-udp.conf -g "daemon on;")
fi 

IFS=: read -ra JAVA_HOST_ARRAY <<< ${JAVA_VERSIONHOSTPAIRS}

if [[ ${#JAVA_HOST_ARRAY} -gt 0 ]]; then 
  INDEX=0
  # for HOST in ${JAVA_HOST_ARRAY[@]}; do 
  #   export HOST
  for VERSIONHOST in ${JAVA_HOST_ARRAY[@]}; do 
    IFS== read -ra VERSIONHOSTPARTS <<< ${VERSIONHOST}
    export VERSION=${VERSIONHOSTPARTS[0]}
    export HOST=${VERSIONHOSTPARTS[1]}    
    export LISTEN_QUERY_PORT=$(( ${MINECRAFT_PROXY_JAVA_QUERY_PORT} + ${INDEX} ))
    export LISTEN_RCON_PORT=$(( ${MINECRAFT_PROXY_JAVA_RCON_PORT} + ${INDEX} ))
    (envsubst < /app/nginx-java-tcp.conf.tmpl > /app/nginx-java-tcp-${HOST}.conf \
      && echo "$(cat /app/nginx-java-tcp-${HOST}.conf)" \
      && echo "running java nginx for ${HOST}.." \
      && nginx -c /app/nginx-java-tcp-${HOST}.conf -g "daemon on;")
    INDEX=$(( ${INDEX} + 1 ))
  done 
fi 

sleep INF
