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


pushd ../
./build.sh $@
popd 

. common 
. .env 

for VERSION in ${VERSION_ARRAY[@]}; do 

  if [[ -n "${SPECVERSION}" && "${VERSION}" != "${SPECVERSION}" ]]; then 
    continue 
  fi 

  HASH=$(cat .jenv | jq -r ".worlds | .[] | select(.version == \"${VERSION}\") | .sha")
  TARGET_PLATFORM=$(cat .jenv | jq -r ".worlds | .[] | select(.version == \"${VERSION}\") | .target_platform")

  echo "Building ${IMAGE}:${VERSION} from ${HASH}.."

  [[ "${TARGET_PLATFORM}" = "minikube" ]] \
    && (
      . ../scripts/minikube-env.sh \
      || (RESULT=$? && echo "Something went wrong sourcing minikube env.." && exit ${RESULT})
    )

  docker build $@ -t ${IMAGE}:${VERSION} --build-arg HASH=${HASH} . 

  [[ "${TARGET_PLATFORM}" = "minikube" ]] && . ../scripts/minikube-env-deactivate.sh

done 


