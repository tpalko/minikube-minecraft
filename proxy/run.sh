#!/bin/bash 

# set -e 

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

function find_host_for_version() {
    
  HOST_CONTAINER_FILTER="^k8s_POD_${IMAGE}-${VERSION}-[a-f0-9]{9,10}-[a-z0-9]{5}_"
  DOCKER_CONTAINER_ID=$(docker ps --filter="name=${HOST_CONTAINER_FILTER}" -q)

  if [[ -z "${DOCKER_CONTAINER_ID}" ]]; then 
    echo "No running container found for ${HOST_CONTAINER_FILTER}"
    return 1 
  fi 

  NEW_HOST=$(docker inspect $(docker ps --filter="name=${HOST_CONTAINER_FILTER}" -q) | jq -r ".[] | .NetworkSettings | .Networks | .bridge | .IPAddress")
  
  if [[ -z "${NEW_HOST}" || "${NEW_HOST}" = "null" ]]; then 
    echo "No IP address found for ${HOST_CONTAINER_FILTER}. Skipping ${VERSION}."
    return 1
  fi 

  VERSION_HOST_ARRAY=(${NEW_HOST})

  if [[ ${#VERSION_HOST_ARRAY[@]} -gt 1 ]]; then 
    echo "Multiple IP addresses found for ${HOST_CONTAINER_FILTER} (${VERSION_HOST_ARRAY[@]}). Skipping ${VERSION}."
    return 1
  fi 

  echo ${NEW_HOST}
}

function scrape_hosts() {

  CONFIG_PATH=$1
  
  # source java 
  pushd ${CONFIG_PATH}

  . common 
  . .env 

  HOSTS_ARRAY=${TYPE}_HOSTS 
  VERSION_HOST_PAIRS_ARRAY=${TYPE}_VERSION_HOST_PAIRS

  for VERSION in ${VERSION_ARRAY[@]}; do 

    echo "Looking for ${TYPE} version ${VERSION} host pod.."  
    NEW_HOST=$(find_host_for_version)

    if [[ $? -eq 0 && -n "${NEW_HOST}" ]]; then 
      echo "Found ${NEW_HOST} for ${VERSION}"
      eval "${HOSTS_ARRAY}+=(${NEW_HOST})"
      eval "${VERSION_HOST_PAIRS_ARRAY}+=(${VERSION}=${NEW_HOST})"
    else 
      echo "${NEW_HOST}"
    fi 
  done 

  popd 

}

# source minikube env 
. ../scripts/minikube-env.sh 

scrape_hosts ../java
scrape_hosts ../bedrock

# clear minikube env 
. ../scripts/minikube-env-deactivate.sh 

if [[ ${#java_HOSTS[@]} -eq 0 && ${#bedrock_HOSTS[@]} -eq 0 ]]; then 
  echo "Neither Java nor Bedrock appears to have any hosts."
  exit 0
fi 

echo "Found Java hosts: ${java_HOSTS[@]}"
echo "Found Bedrock hosts: ${bedrock_HOSTS[@]}"

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
 
[[ -z "${MINIKUBE_IP}" || "${MINIKUBE_INTERFACE}" = "br-" ]] \
  && echo "minikube IP or interface could not be identified. please exit any minikube docker environment" && exit 1

function clear_routes() {
  
  readarray ROUTE_CLEAR_CMD <<< "$(sudo route -ne \
    | grep -E "^172\.17\.0\.[0-9]\s+${MINIKUBE_IP}\s+255\.255\.255\.255\s+UGH\s+0\s+0\s+0\s+${MINIKUBE_INTERFACE}$" \
    | awk  '{ print "sudo route del -net "$1" gw "$2" netmask "$3" dev "$8 }')"

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
  for HOST in ${bedrock_HOSTS[@]} ${java_HOSTS[@]}; do 
    NEW_ROUTE="route add -net ${HOST} gw ${MINIKUBE_IP} netmask 255.255.255.255 dev ${MINIKUBE_INTERFACE}"
    echo "Adding route:"
    echo "${NEW_ROUTE}"
    confirm 
    sudo ${NEW_ROUTE} \
      || (
          [[ $? -eq 127 ]] \
          && echo "mayhaps not privileged?" \
          || echo "mayhaps the route is already in place.." 
      )
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
  
  JAVA_HOST_STRING="$(echo ${java_VERSION_HOST_PAIRS[@]})"
  BEDROCK_HOST_STRING="$(echo ${bedrock_VERSION_HOST_PAIRS[@]})"

  # JAVA_HOST_STRING="$(echo ${JAVA_HOSTS[@]})"
  DOCKER_RUN_CMD="docker run -d --env-file .env \
    -e JAVA_VERSION_HOST_PAIRS=${JAVA_HOST_STRING// /:} \
    -e BEDROCK_VERSION_HOST_PAIRS=${BEDROCK_HOST_STRING// /:} \
    ${NAMEPARAM} ${NETWORKPARAM} minecraft-proxy:latest"
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
