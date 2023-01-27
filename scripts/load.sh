#!/bin/bash 

############################################################
#
# Unpacks a backup file to be used by the local multiplayer server.
# Theoretically, supports both the host docker container and the minikube-based
# servers, as well as both bedrock and java, theoretically.
#
# The "loading" process must account for differences between bedrock 
# and java in managing live world data. Bedrock keeps world folders in a 
# "worlds" subfolder, while Java keeps world folders directly in the server 
# folder, along with server.properties, etc. Both will load the world on 
# startup based on "level-name", a server.properties field, so an arbitrary 
# number of worlds can be present on the server at any time, but the server
# i.e. pod/env must be redeployed to switch between worlds. 
# Redeploying (at the time of this writing) means destroying 
# the environment volumes and all and recreating it, making loading, switching or even persisting  
# world data all but impossible. The PV/PVC resource templates must be 
# separated from the Deployment resource templates to fix this. Until then, because backups do run,
# world data is not lost between deploys but every redeploy will generate a new world.

set -e 

function usage() {
  echo "Usage: $0 -f(orce) -k(8s) -b <BACKUP FILE>"
  # ./load.sh [-k] [-f] -b <world name>
}

FORCE=0
K8S=0

while [[ -n "$1" ]]; do 
  case $1 in 
    -v)           VERSION=$2
                  shift; shift;
                  ;;
    -f)           FORCE=1
                  shift 
                  ;;
    -b)           BACKUP_FILE=$2
                  shift; shift;
                  ;;
    -k)           K8S=1
                  shift 
                  ;;
    *)            usage && exit 1
                  ;;
  esac 
done 

if [[ -z "${BACKUP_FILE}" || -z "${VERSION}" ]]; then 
  usage 
  exit 1
fi 

if [[ ! -f "${BACKUP_FILE}" ]]; then 
  echo "${BACKUP_FILE} does not exist"
  exit 1
fi 

eval $(while read LINE; do echo export ${LINE}; done < <(cat .env))

MEMBER=${WORLD_BASE}
echo "-${IFS}-"
IFS=/; read -ra BASEPARTS <<< "${WORLD_BASE}"; IFS=;
STRIP=$(( ${#BASEPARTS[@]} - 1 ))
echo "${STRIP} components stripping for ${WORLD_BASE}"

if [[ ${K8S} -eq 1 ]]; then 
 
  MINIKUBE_WORLD_PATH=${VOLUME_BASE}-${VERSION}/world

  echo "Loading into minikube.."
  
  if [[ $(minikube ssh "find ${MINIKUBE_WORLD_PATH} -type f" | wc -l) -gt 0 ]]; then 
    echo "There is world data loaded in ${MINIKUBE_WORLD_PATH} already."
    echo -n "Do you want to destroy it permanently? y/N "
    read DESTROY
    if [[ "${DESTROY}" = "y" ]]; then
      minikube ssh "sudo rm -rf ${MINIKUBE_WORLD_PATH}/*"
    else 
      exit 1
    fi 
  fi 
  
  rm -rf _working_temp
  mkdir -p _working_temp 

  sudo tar -xzvf ${BACKUP_FILE} -C _working_temp --strip-components ${STRIP}
  
  sudo chown -R ${USER}:${USER} _working_temp
  
  docker cp "_working_temp/${WORLD_NAME}" minikube:${MINIKUBE_WORLD_PATH}
  minikube ssh "mv \"${MINIKUBE_WORLD_PATH}/${WORLD_NAME}/*\" ${MINIKUBE_WORLD_PATH}"

  rm -rf _working_temp
  
  minikube ssh "sudo chown -R 999:999 ${MINIKUBE_WORLD_PATH}"
  echo "${BACKUP_FILE} is loaded into minikube:${MINIKUBE_WORLD_PATH}"
  echo "Go ahead and ./deploy.sh the server now"
  
else 
  
  TARGET=live/world

  CONTAINER_ID=$(docker ps --filter="name=${IMAGE}" -q)

  if [[ -n "${CONTAINER_ID}" && ${FORCE} -ne 1 ]]; then 
    echo "A minecraft-server container appears to be running (name=${IMAGE}). It is strongly "
    echo "advised that you don't load in world data while a server may be accessing "
    echo "the live folder. At least exit the world and turn off saves."
    exit 1
  fi 

  if [[ "$(find ${TARGET} -type f | wc -l)" != "0" ]]; then 
    echo "There is world data loaded in ${TARGET} already."
    echo -n "Do you want to destroy it permanently? y/N "
    read DESTROY
    if [[ "${DESTROY}" = "y" ]]; then
      sudo rm -vrf ${TARGET}/*
    fi 
  fi 
  
  sudo tar -C ${TARGET} --strip-components ${STRIP} -xzvf ${BACKUP_FILE} ${MEMBER}
  
  sudo chown -R 999:999 ${TARGET}
  echo "${BACKUP_FILE} is loaded into ${TARGET}"
  echo "Go ahead and ./run.sh the server now if it's not already running!"
  
fi 
