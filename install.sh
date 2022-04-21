#!/bin/bash 

ACTION=$1


for SCRIPT in build.sh deploy.sh mcshell.sh run.sh load.sh; do 
  for DEPLOY in java bedrock; do
    if [[ "${ACTION}" = "install" || -z "${ACTION}" ]]; then       
      ln -svf ../scripts/${SCRIPT} ${DEPLOY}/${SCRIPT%%.sh}
    elif [[ "${ACTION}" = "uninstall" ]]; then
      rm -vf ${DEPLOY}/${SCRIPT%%.sh}
    fi  
  done 
done 
