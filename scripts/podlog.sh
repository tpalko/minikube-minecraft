#!/bin/bash 

. .env 

kubectl logs -f $(kubectl get pod | grep ${IMAGE} | awk '{ print $1 }')
