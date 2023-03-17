#!/bin/bash 

MINIKUBE_CMD=/home/debian/tpalko/.asdf/shims/minikube

function crontab_locked() {
    [[ -f ${CRONTAB_LOCK_FILE} ]] 2>/dev/null
}

function backup_locked() {
    ${MINIKUBE_CMD} ssh "[[ -f ${MINIKUBE_LOG_FOLDER}/backup.lock ]]" 2>/dev/null
}

function lock_crontab() {
    echo "Creating ${CRONTAB_LOCK_FILE}"
    touch ${CRONTAB_LOCK_FILE}
}

function copy_backups() {
    # BACKUPS_FOLDER=$(${MINIKUBE_CMD} ssh "du -hxd 1 ${MINIKUBE_VOLUMES_FOLDER}/backups/${WORLD_NAME} | tail -n 1")
    # echo "${BACKUPS_FOLDER}"
    # BACKUP_SIZE=$(echo ${BACKUPS_FOLDER} | awk '{ print $1 }')
    echo "Copying ${BACKUP_CP_CMD} -> ${PWD}/backups/${VERSION}/${WORLD_NAME}"
    
    MINIKUBE_BACKUPS=$(${MINIKUBE_CMD} ssh "find ${MINIKUBE_VOLUMES_FOLDER}/backups/${WORLD_NAME} -wholename \"${MINIKUBE_VOLUMES_FOLDER}/backups/${WORLD_NAME}/${WORLD_NAME}-*.tar.gz\"" | sort -rn)
    echo "Found $(echo "${MINIKUBE_BACKUPS}" | wc -l) remote backups in ${MINIKUBE_VOLUMES_FOLDER}/backups/${WORLD_NAME}"
    echo " v v v"
    echo "${MINIKUBE_BACKUPS}"
    echo " ^ ^ ^"

    while read BACKUP_FILE; do 
      BACKUP_FILE=${BACKUP_FILE//[$'\t\r\n']}
      if [[ -z "${BACKUP_FILE}" ]]; then 
        continue 
      fi 
      echo ""
      echo "********************************"      
      echo "Remote filepath: ${BACKUP_FILE}"
    #   echo "$(echo -n ${BACKUP_FILE} | od -c)"
      BACKUP_FILE_BASENAME=$(basename ${BACKUP_FILE})
    #   echo "Base name: ${BACKUP_FILE_BASENAME}"
      LOCAL_BACKUP_FILE="${PWD}/backups/${VERSION}/${WORLD_NAME}/${BACKUP_FILE_BASENAME}"
      echo "Looking for local copy at ${LOCAL_BACKUP_FILE}"      
      if [[ -f ${LOCAL_BACKUP_FILE} ]]; then 
        echo "Found ${LOCAL_BACKUP_FILE}"
      else
        echo "Not found!"        
        FULL_CP_CMD="${BACKUP_CP_CMD}/${BACKUP_FILE_BASENAME} backups/${VERSION}/${WORLD_NAME}/"
        echo "${FULL_CP_CMD}"
        ${FULL_CP_CMD}        
      fi
    done <<< ${MINIKUBE_BACKUPS}

}

function unlock_crontab() {
    echo "Removing ${CRONTAB_LOCK_FILE}"
    rm -vf touch ${CRONTAB_LOCK_FILE}
}

function crontab_log() {
    MSG="$1"
    echo "${MSG}" | tee -a ${LOG_FILE}
}

echo $@

if [[ -z "${WORLD_NAME}" || -z "${VERSION}" || -z "${BACKUP_CP_CMD}" ]]; then 
    echo "WORLD_NAME, VERSION, and BACKUP_CP_CMD must be set"
    exit 1
fi 

CURR_FOLDER=$(dirname $0)

pushd ${CURR_FOLDER}

. common 
. .env 

MINIKUBE_VOLUMES_FOLDER=${VOLUME_BASE}-${VERSION}
MINIKUBE_LOG_FOLDER=${MINIKUBE_VOLUMES_FOLDER}/log
HOST_LOG_FOLDER=log/${VERSION}
LOG_FILE=${HOST_LOG_FOLDER}/crontab.log
CRONTAB_LOCK_FILE=${HOST_LOG_FOLDER}/crontab.lock

echo "Creating ${HOST_LOG_FOLDER}.."
mkdir -vp ${HOST_LOG_FOLDER}

crontab_log "||||||||||||||||||||||||||||||||||||||||||||||||||||"
crontab_log "|||"
crontab_log "|||       crontab entrypoint "
crontab_log "|||       $(date)"
crontab_log "|||"
crontab_log "|||       Type: ${TYPE}"
crontab_log "|||       World name: ${WORLD_NAME}"
crontab_log "|||       Version: ${VERSION}"
crontab_log "|||       Host logs: ${HOST_LOG_FOLDER}"
crontab_log "|||       Minikube logs: ${MINIKUBE_LOG_FOLDER}"
crontab_log "|||       Crontab lock: ${CRONTAB_LOCK_FILE}"
crontab_log "|||       Backup copy command: ${BACKUP_CP_CMD}"
crontab_log "|||"
crontab_log "|||       Logging to ${LOG_FILE}"
crontab_log "|||"
crontab_log "|||"

ATTEMPT_COUNT=0

(
    [[ ! $(crontab_locked) ]] \
        && (
            lock_crontab \
            && echo "We just locked crontab, going to work now" \
            && while [[ ${ATTEMPT_COUNT} -lt 5 ]]; do 
                [[ ! $(backup_locked) ]] \
                    && (
                        echo "Backup isn't running, copying now" \
                            && copy_backups \
                            && echo "Copy succeeded" \
                        || echo "Copy failed"                        
                    ) && break \
                    || (
                        echo "Backup is running, we sleep now (ATTEMPT_COUNT=${ATTEMPT_COUNT})" \
                            && ATTEMPT_COUNT=$(( ${ATTEMPT_COUNT} + 1 )) \
                            && sleep 60
                    )
            done \
            && unlock_crontab \
            && echo "We just unlocked crontab, have a nice day!"
        ) \
        || (echo "Crontab is locked, someone else is already persistently trying to work, we go away now" && exit 1)
) | tee -a ${LOG_FILE} 2>&1

crontab_log "|||"
crontab_log "|||       completed "
crontab_log "|||       $(date)"
crontab_log "|||"
crontab_log "||||||||||||||||||||||||||||||||||||||||||||||||||||"