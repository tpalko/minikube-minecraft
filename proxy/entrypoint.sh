#!/bin/bash

set -e 

env | grep -E "^MINECRAFT_"

IFS=: read -ra BEDROCK_HOST_ARRAY <<< ${BEDROCK_VERSION_HOST_PAIRS}

if [[ ${#BEDROCK_HOST_ARRAY} -gt 0 ]]; then 
  INDEX=0
  for VERSIONHOST in ${BEDROCK_HOST_ARRAY[@]}; do 
    
    IFS== read -ra VERSIONHOSTPARTS <<< ${VERSIONHOST}
    export VERSION=${VERSIONHOSTPARTS[0]}
    export HOST=${VERSIONHOSTPARTS[1]}    
    export LISTEN_PORT=$(( ${MINECRAFT_PROXY_BEDROCK_PORT} + ${INDEX} ))
    TCP_CONF=/app/nginx-bedrock-tcp-${HOST}.conf 
    UDP_CONF=/app/nginx-bedrock-udp-${HOST}.conf

    (envsubst < /app/nginx-bedrock-tcp.conf.tmpl > ${TCP_CONF} \
      && envsubst < /app/nginx-bedrock-udp.conf.tmpl > ${UDP_CONF} \
      && echo "$(cat ${TCP_CONF})" \
      && echo "$(cat ${UDP_CONF})" \
      && echo "running bedrock nginxes.." \
      && nginx -c ${TCP_CONF} -g "daemon on;" \
      && nginx -c ${UDP_CONF} -g "daemon on;")

    INDEX=$(( ${INDEX} + 1 ))
  done 
fi 

IFS=: read -ra JAVA_HOST_ARRAY <<< ${JAVA_VERSION_HOST_PAIRS}

if [[ ${#JAVA_HOST_ARRAY} -gt 0 ]]; then 
  INDEX=0
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
