#!/bin/bash

set -e 

SPECVERSION=

while [[ $# -gt 0 ]]; do 
  case $1 in 
    -v)     SPECVERSION=$2
            shift; shift 
            ;;
      *)    echo "Ignoring $1"
            shift 
            ;;
  esac 
done 

. common
. .env 

for VERSION in ${VERSION_ARRAY[@]}; do 

  if [[ -n "${SPECVERSION}" && "${VERSION}" != "${SPECVERSION}" ]]; then 
    continue 
  fi 

  HASH=$(version_parameter sha)
  TARGET_PLATFORM=$(version_parameter target_platform)

  echo "Building ${IMAGE}:${VERSION} from ${HASH} into ${TARGET_PLATFORM}"  

  if [[ "${TARGET_PLATFORM}" = "minikube" ]]; then 
    echo "Entering minikube environment (TARGET_PLATFORM=${TARGET_PLATFORM})"
    . ../scripts/minikube-env.sh
  else 
    echo "Not entering minikube environment (TARGET_PLATFORM=${TARGET_PLATFORM})"
  fi 

  pushd ../
  ./build.sh $@
  popd 

  docker build $@ -t ${IMAGE}:${VERSION} --build-arg HASH=${HASH} . 

  if [[ "${TARGET_PLATFORM}" = "minikube" ]]; then 
    . ../scripts/minikube-env-deactivate.sh
  fi 
  
done 


