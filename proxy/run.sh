#!/bin/bash 

set -e 

case $1 in 
  start|stop)   ACTION=$1
                ;;
  *)            echo "Usage: $0 start|stop"
                exit 1
                ;;
esac 

MINIKUBE_IP=$(minikube ip)
MINIKUBE_INTERFACE=br-$(docker network ls --filter="name=minikube" -q)
NETWORK=host
NAME=minecraft-proxy
EXISTING_PROXY_CONTAINER=$(docker ps --filter="name=${NAME}" -q)
DEAD_CONTAINER=$(docker ps -qa --filter="name=${NAME}")
INTERACTIVE=${INTERACTIVE:=0}

# source minikube env 
. ../scripts/minikube-env.sh 
# source java 
. ../java/.env 

if [[ -n "${VERSIONS}" ]]; then 
  IFS=: read -ra VERSIONARRAY <<< ${VERSIONS}
else
  VERSIONARRAY=(${VERSION})
fi 

echo "Standing up proxy for ${#VERSIONARRAY[@]} Java versions: ${VERSIONARRAY[@]}"

JAVA_HOSTS=()
JAVA_VERSIONHOSTPAIRS=()

for VERSION in ${VERSIONARRAY[@]}; do 
  
  IFS==	read -ra PARTS <<< ${VERSION}
  VERSION=${PARTS[0]}
  HASH=${PARTS[1]}
  
  export VERSION 
  export VERSION_HYPHEN=${VERSION//./-}
  
  HOST_CONTAINER_FILTER="POD_${IMAGE}-${VERSION}"

  echo "Looking for ${HOST_CONTAINER_FILTER} pod.."
  
  NEW_HOST=$(docker inspect $(docker ps --filter="name=${HOST_CONTAINER_FILTER}" -q) | jq -r ".[] | .NetworkSettings | .Networks | .bridge | .IPAddress")
  
  if [[ -z "${NEW_HOST}" ]]; then 
    echo "No IP address found for ${HOST_CONTAINER_FILTER}. Skipping ${VERSION}."
    continue 
  fi 

  VERSION_HOST_ARRAY=(${VERSION})

  if [[ ${#VERSION_HOST_ARRAY[@]} -gt 1 ]]; then 
    echo "Multiple IP addresses found for ${HOST_CONTAINER_FILTER} (${VERSION_HOST_ARRAY[@]}). Skipping ${VERSION}."
    continue 
  fi 

  echo "Found ${NEW_HOST} for ${VERSION}"
  JAVA_HOSTS+=(${NEW_HOST})
  JAVA_VERSIONHOSTPAIRS+=(${VERSION}=${NEW_HOST})
  # MINECRAFT_PROXY_JAVA_UPSTREAM_HOST=$(docker inspect $(docker ps --filter="name=POD_${IMAGE}" -q) | jq -r ".[] | .NetworkSettings | .Networks | .bridge | .IPAddress")
done 


# source bedrock 
. ../bedrock/.env 

echo "Looking for ${IMAGE} pod.."
MINECRAFT_PROXY_BEDROCK_UPSTREAM_HOST=$(docker inspect $(docker ps --filter="name=POD_${IMAGE}" -q) 2>/dev/null | jq -r ".[] | .NetworkSettings | .Networks | .bridge | .IPAddress")

# clear minikube env 
. ../scripts/minikube-env-deactivate.sh 


if [[ ${#JAVA_HOSTS[@]} -eq 0 && -z "${MINECRAFT_PROXY_BEDROCK_UPSTREAM_HOST}" ]]; then 
  echo "Neither Java nor Bedrock appears to have any hosts."
  exit 1
fi 

echo "Found Java hosts: ${JAVA_HOSTS[@]}"
echo "Found MINECRAFT_PROXY_BEDROCK_UPSTREAM_HOST=${MINECRAFT_PROXY_BEDROCK_UPSTREAM_HOST}"

. .env 

function confirm() {
  if [[ "${INTERACTIVE}" != "0" ]]; then 
    echo -n "OK? y/N "
    read OK
    if [[ "${OK}" != "y" ]]; then 
      echo "Quitting.."
      exit 0
    fi 
  fi 
}
 
[[ -z "${MINIKUBE_IP}" || "${MINIKUBE_INTERFACE}" = "br-" ]] && echo "minikube IP or interface could not be identified. please exit any minikube docker environment" && exit 1

function clear_routes() {
  readarray ROUTE_CLEAR_CMD <<< "$(sudo route -ne | grep -E "^172\.17\.0\.[0-9]\s+${MINIKUBE_IP}\s+255\.255\.255\.255\s+UGH\s+0\s+0\s+0\s+${MINIKUBE_INTERFACE}$" | awk  '{ print "sudo route del -net "$1" gw "$2" netmask "$3" dev "$8 }')"
  [[ -z "${ROUTE_CLEAR_CMD}" ]] && echo "No routes to clear" && return 
  echo "Clearing routes:"
  echo "${ROUTE_CLEAR_CMD[@]}"
  confirm 
  for ROUTE_CLEAR_LINE in "${ROUTE_CLEAR_CMD[@]}"; do 
    echo "Running ${ROUTE_CLEAR_LINE}"
    ${ROUTE_CLEAR_LINE}
  done 
}

function add_route() {
  for HOST in $MINECRAFT_PROXY_BEDROCK_UPSTREAM_HOST ${JAVA_HOSTS[@]}; do 
    NEW_ROUTE="route add -net ${HOST} gw ${MINIKUBE_IP} netmask 255.255.255.255 dev ${MINIKUBE_INTERFACE}"
    echo "Adding route:"
    echo "${NEW_ROUTE}"
    confirm 
    sudo ${NEW_ROUTE} || ([[ $? -eq 127 ]] && echo "mayhaps not privileged?" || echo "mayhaps the route is already in place.." )
  done 
}

function remove_container() {
  if [[ "${REPLACE}" = "y" ]]; then 
    DOCKER_STOP_CMD="docker stop ${NAME}"
    DOCKER_REMOVE_CMD="docker rm ${NAME}"
    echo "Removing ${NAME}"
    ${DOCKER_STOP_CMD} && (${DOCKER_REMOVE_CMD} 2>/dev/null || true)
  fi 
}

function build_image() {
  DOCKER_BUILD_CMD="docker build -t minecraft-proxy:latest ."  
  echo "Building new image.."
  ${DOCKER_BUILD_CMD}
}

function run_container() {
  NETWORKPARAM=
  NAMEPARAM=
  [[ -n "${NETWORK}" ]] && NETWORKPARAM="--network ${NETWORK}"
  [[ -n "${NAME}" ]] && NAMEPARAM="--name ${NAME}"
  # -- published ports are discarded when using host network mode
  # -p ${MINECRAFT_PROXY_QUERY_PORT}:${MINECRAFT_PROXY_QUERY_PORT} \
  # -p ${MINECRAFT_PROXY_RCON_PORT}:${MINECRAFT_PROXY_RCON_PORT} \
  if [[ -z "${EXISTING_PROXY_CONTAINER}" && -n "${DEAD_CONTAINER}" ]]; then 
    echo "Removing dead container.."
    docker rm ${NAME}
  fi 
  
  JAVA_HOST_STRING="$(echo ${JAVA_VERSIONHOSTPAIRS[@]})"
  # JAVA_HOST_STRING="$(echo ${JAVA_HOSTS[@]})"
  DOCKER_RUN_CMD="docker run -d --env-file .env -e JAVA_VERSIONHOSTPAIRS=${JAVA_HOST_STRING// /:} -e MINECRAFT_PROXY_BEDROCK_UPSTREAM_HOST=${MINECRAFT_PROXY_BEDROCK_UPSTREAM_HOST} ${NAMEPARAM} ${NETWORKPARAM} minecraft-proxy:latest"
  echo "--------------------------------------------------"
  echo "-- Starting new comtainer.. $(date)"
  echo "${DOCKER_RUN_CMD}"
  echo ""
  ${DOCKER_RUN_CMD}
}

REPLACE=
if [[ -n "${EXISTING_PROXY_CONTAINER}" ]]; then 
  echo "${NAME} is already running. We still stop it."
  confirm 
  REPLACE=y
fi 

remove_container && clear_routes

if [[ "${ACTION}" = "start" ]]; then 
   add_route \
    && build_image \
    && run_container
elif [[ "${ACTION}" = "stop" ]]; then 
  echo "Have a nice day!"
fi 
