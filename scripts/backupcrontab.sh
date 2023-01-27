#!/bin/bash 

# -- run from minecraft/java or minecraft/bedrock 

. .env 

printf "$(crontab -l)\n#${IMAGE} minikube world volume backup\n1,16,31,46 * * * * docker cp minikube:/home/docker/${IMAGE}/volumes/backups ${PWD}/\n" | crontab -
