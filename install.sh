#!/bin/bash 

ACTION=$1

for SCRIPT in envmanager.py common.sh cron.sh build.sh deploy.sh mcshell.sh run.sh load.sh; do 
  STRIPPED_SCRIPT_FILE=${SCRIPT%%.sh}
  STRIPPED_SCRIPT_FILE=${STRIPPED_SCRIPT_FILE%%.py}  
  for DEPLOY in java bedrock; do
    echo "Doing ${DEPLOY}"
    TARGET="${DEPLOY}/${STRIPPED_SCRIPT_FILE}"
    echo "Link source: ../scripts/${SCRIPT}"
    echo "Link target: ${TARGET}"
    if [[ "${ACTION}" = "install" || -z "${ACTION}" ]]; then
      echo "Creating!"  
      ln -svf ../scripts/${SCRIPT} ${TARGET}
    elif [[ "${ACTION}" = "uninstall" ]]; then
      rm -vf ${TARGET}
    fi  
  done 
done 
