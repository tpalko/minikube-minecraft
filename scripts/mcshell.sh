#!/bin/bash 

. .env 

function usage() {
  printf "Usage:\n\n"
  printf "\t$0 [version] ACTION\n\n"
  printf "ACTION:\n\n"
  printf "\tshell - shell into running server container\n"
  printf "\tlogs - tail running server container logs\n\n"
}

VERSION=
if [[ $# -gt 1 ]]; then 
  VERSION=$1
  shift 
fi 

ACTION=
if [[ $# -gt 0 ]]; then 
  ACTION=$1
  shift 
fi 

MATCH="k8s_${IMAGE}_${IMAGE}-${VERSION}"

. ../scripts/minikube-env.sh

CONTAINER=$(docker ps --filter="name=${MATCH}" --filter="status=running" -q)

if [[ -z "${CONTAINER}" ]]; then 
  echo "No container matching ${MATCH}"
  exit 1
fi 

case ${ACTION} in 
  shell)        echo "shelling into ${CONTAINER}"
                docker exec -itu 0 ${CONTAINER} /bin/bash
                ;;
  logs)         echo "Logging ${CONTAINER}"
                docker logs -f ${CONTAINER}
                ;;
  *)            usage; exit 1;
esac 

. ../scripts/minikube-env-deactivate.sh
