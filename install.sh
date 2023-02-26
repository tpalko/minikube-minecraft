#!/bin/bash 

ACTION=$1

for SCRIPT in envmanager.py common.sh build.sh deploy.sh mcshell.sh run.sh load.sh; do 
  TARGET=${SCRIPT%%.sh}
  TARGET=${TARGET%%.py}
  for DEPLOY in java bedrock; do
    TARGET=${DEPLOY}/${TARGET} 
    if [[ "${ACTION}" = "install" || -z "${ACTION}" ]]; then       
      ln -svf ../scripts/${SCRIPT} ${TARGET}
    elif [[ "${ACTION}" = "uninstall" ]]; then
      rm -vf ${TARGET}
    fi  
  done 
done 
