#!/bin/bash 

. common 
. .env 

function usage() {
  printf "Usage:\n\n"
  printf "\t$0 [-v VERSION]\n\n"
}

VERSION=

while [[ $# -gt 0 ]]; do 
  case $1 in 
    -v)     VERSION=$2
            shift; shift 
            ;;
  esac 
done 

if [[ -n "${VERSION}" ]]; then 
  VERSION_ARRAY=(${VERSION})
fi 

for VERSION in ${VERSION_ARRAY[@]}; do 

  TARGET_PLATFORM=$(version_parameter target_platform)

  case ${TARGET_PLATFORM} in 
    minikube)   MATCH="k8s_${IMAGE}_${IMAGE}-${VERSION}-[a-f0-9]{9,10}-[a-z0-9]{5}_"
                . ../scripts/minikube-env.sh
                ;;
    docker)     MATCH="${IMAGE}-${VERSION}"
                ;;
  esac 

  CONTAINER=$(docker ps --filter="name=${MATCH}" --filter="status=running" -q)

  echo ${VERSION} ${CONTAINER}

  [[ "${TARGET_PLATFORM}" = "minikube" ]] && . ../scripts/minikube-env-deactivate.sh

done 
