#!/bin/bash 

for NETWORK in $(docker network ls -q); do 
  NETWORKJ=$(docker network inspect ${NETWORK})
  NAME=$(echo "${NETWORKJ}" | jq -r ".[] | .Name")
  DRIVER=$(echo "${NETWORKJ}" | jq -r ".[] | .Driver")
  CONFIG=$(echo "${NETWORKJ}" | jq -r ".[] | .IPAM.Config")
  CONTAINERS=$(echo "${NETWORKJ}" | jq -r ".[] | .Containers")
  
  echo "${NAME} (${DRIVER})"
  echo "${CONFIG}"
  echo "${CONTAINERS}"
done
