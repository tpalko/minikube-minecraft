#!/bin/bash

env | grep -E "^MINECRAFT_"

(envsubst < /app/nginx-tcp.conf.tmpl > /app/nginx-tcp.conf \
  && envsubst < /app/nginx-udp.conf.tmpl > /app/nginx-udp.conf \
  && echo "$(cat /app/nginx-udp.conf)" \
  && echo "$(cat /app/nginx-tcp.conf)" \
  && echo "running nginxes.." \
  && (ping ${MINECRAFT_PROXY_JAVA_UPSTREAM_HOST} -c 1 || echo "oh well..?") \
  && (ping ${MINECRAFT_PROXY_BEDROCK_UPSTREAM_HOST} -c 1 || echo "oh well..?") \
  && nginx -c /app/nginx-udp.conf -g "daemon on;" \
  && nginx -c /app/nginx-tcp.conf -g "daemon off;"
)
