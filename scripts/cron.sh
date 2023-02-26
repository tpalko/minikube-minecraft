#!/bin/bash 

function crontab_locked() {
    [[ -f ${CRONTAB_LOCK_FILE} ]] 2>/dev/null
}

function backup_locked() {
    minikube ssh "[[ -f ${MINIKUBE_LOG_FOLDER}/backup.lock ]]" 2>/dev/null
}

function lock_crontab() {
    echo "Creating ${CRONTAB_LOCK_FILE}"
    touch ${CRONTAB_LOCK_FILE}
}

function copy_backups() {
    BACKUP_SIZE=$(minikube ssh "du -hxd 1 ${MINIKUBE_VOLUMES_FOLDER}/backups/${WORLD_NAME} | tail -n 1" | awk '{ print $1 }')
    echo "Copying ${BACKUP_SIZE}: ${BACKUP_CP_CMD} ${CURR_FOLDER}/backups/${VERSION}"
    # ${BACKUP_CP_CMD} "${CURR_FOLDER}/backups/${VERSION}/" 2>&1
   
    MINIKUBE_BACKUPS=$(minikube ssh "find ${MINIKUBE_VOLUMES_FOLDER}/backups/${WORLD_NAME} -wholename \"${MINIKUBE_VOLUMES_FOLDER}/backups/${WORLD_NAME}/${WORLD_NAME}-*.tar.gz\"")

    while read BACKUP_FILE; do 
      echo "Found ${BACKUP_FILE} remotely.."
      FILENAME=$(basename ${BACKUP_FILE})
      LOCAL_BACKUP_FILE="${CURR_FOLDER}/backups/${VERSION}/${WORLD_NAME}/${FILENAME}"
      echo "Looking for ${FILENAME} locally"
      if [[ -f ${LOCAL_BACKUP_FILE} ]]; then 
        echo "${LOCAL_BACKUP_FILE}"
      else
        echo "Not found!"
        docker cp minikube:${MINIKUBE_VOLUMES_FOLDER}/backup/${WORLD_NAME}/${FILENAME} ${CURR_FOLDER}/backups/${VERSION}/${WORLD_NAME}/
        echo "${MINIKUBE_VOLUMES_FOLDER}/backup/${WORLD_NAME}/${FILENAME} --> ${CURR_FOLDER}/backups/${VERSION}/${WORLD_NAME}"
      fi
    done < <(echo "${MINIKUBE_BACKUPS}")

}

function unlock_crontab() {
    echo "Removing ${CRONTAB_LOCK_FILE}"
    rm -vf touch ${CRONTAB_LOCK_FILE}
}

function crontab_log() {
    MSG="$1"
    echo "${MSG}" | tee -a ${LOG_FILE}
}

if [[ -z "${TYPE}" || -z "${VERSION}" || -z "${BACKUP_CP_CMD}" ]]; then 
    echo "TYPE, VERSION, and BACKUP_CP_CMD must be set"
    exit 1
fi 

CURR_FOLDER=$(dirname $0)/../${TYPE}

mkdir -p ${CURR_FOLDER}/log/${TYPE}/${VERSION}

MINIKUBE_VOLUMES_FOLDER=minecraft/${TYPE}/volumes-${VERSION}
MINIKUBE_LOG_FOLDER=${MINIKUBE_VOLUMES_FOLDER}/log
HOST_LOG_FOLDER=${CURR_FOLDER}/log/${TYPE}/${VERSION}
LOG_FILE=${HOST_LOG_FOLDER}/crontab.log
CRONTAB_LOCK_FILE=${HOST_LOG_FOLDER}/crontab.lock

crontab_log "||||||||||||||||||||||||||||||||||||||||||||||||||||"
crontab_log "|||"
crontab_log "|||       crontab entrypoint "
crontab_log "|||       $(date)"
crontab_log "|||"
crontab_log "|||       Type: ${TYPE}"
crontab_log "|||       Version: ${VERSION}"
crontab_log "|||       Host logs: ${HOST_LOG_FOLDER}"
crontab_log "|||       Minikube logs: ${MINIKUBE_LOG_FOLDER}"
crontab_log "|||       Crontab lock: ${CRONTAB_LOCK_FILE}"
crontab_log "|||       Backup copy command: ${BACKUP_CP_CMD}"
crontab_log "|||"
crontab_log "|||       Logging to ${LOG_FILE}"
crontab_log "|||"
crontab_log "|||"

crontab_locked
CRONTAB_LOCKED=$?
backup_locked
BACKUP_LOCKED=$?

(
    ([[ ${CRONTAB_LOCKED} -ne 0 ]] || [[ ${BACKUP_LOCKED} -ne 0 ]]) \
        && (
            (lock_crontab \
                && copy_backups \
                || echo "Something failed in backup") && unlock_crontab
        ) || echo "something is locked (CRONTAB_LOCKED=${CRONTAB_LOCKED} BACKUP_LOCKED=${BACKUP_LOCKED})"
) | tee -a ${LOG_FILE} 2>&1
