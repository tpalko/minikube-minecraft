#!/bin/bash 

. common 
. .env 

function usage() {
  printf "Usage:\n\n"
  printf "\t$0 ACTION -v VERSION\n\n"
  printf "ACTION:\n\n"
  printf "\tshell - shell into running server container\n"
  printf "\tlogs - tail running server container logs\n\n"
}

case $1 in 
  shell|logs)   ACTION=$1
                shift 
                echo "Action: ${ACTION}"
                ;;
  *)            usage 
                exit 1
                ;;
esac 

VERSION=

while [[ $# -gt 0 ]]; do 
  case $1 in 
    -v)     VERSION=$2
            shift; shift 
            ;;
  esac 
done 

if [[ -z "${VERSION}" ]]; then 
  usage 
  exit 1
fi 

TARGET_PLATFORM=$(version_parameter target_platform)

case ${TARGET_PLATFORM} in 
  minikube)   MATCH="k8s_${IMAGE}_${IMAGE}-${VERSION}-[a-f0-9]{9,10}-[a-z0-9]{5}_"
              . ../scripts/minikube-env.sh
              ;;
  docker)     MATCH="${IMAGE}-${VERSION}"
              ;;
esac 

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
esac 

[[ "${TARGET_PLATFORM}" = "minikube" ]] && . ../scripts/minikube-env-deactivate.sh
