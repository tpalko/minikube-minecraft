#!/bin/bash

set -e 

SPECVERSION=

while [[ $# -gt 0 ]]; do 
  case $1 in 
    -v)     SPECVERSION=$2
            shift; shift 
            ;;
  esac 
done 

. ../scripts/minikube-env.sh 

MINIKUBE_ENV_RESULT=$?

[[ ${MINIKUBE_ENV_RESULT} -gt 0 ]] && echo "Something went wrong sourcing minikube env.." && exit ${MINIKUBE_ENV_RESULT}

pushd ../
./build.sh $@
popd 

. .env 

VERSION_ARRAY=($(cat .jenv | jq -r ".worlds | .[] | .version"))
echo "Found ${#VERSION_ARRAY[@]} versions: ${VERSION_ARRAY[@]}"

for VERSION in ${VERSION_ARRAY[@]}; do 

  if [[ -n "${SPECVERSION}" && "${VERSION}" != "${SPECVERSION}" ]]; then 
    continue 
  fi 

  HASH=$(cat .jenv | jq -r ".worlds | .[] | select(.version == \"${VERSION}\") | .sha")

  echo "Building ${IMAGE}:${VERSION} from ${HASH}.."

  docker build $@ -t ${IMAGE}:${VERSION} --build-arg HASH=${HASH} . 

done 

. ../scripts/minikube-env-deactivate.sh
