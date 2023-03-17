#!/bin/bash 

###############################
#
# `deploy` creates and starts or destroys the server
# if provided with -w WORLD_NAME, the server and backup job use that name
# and reasonable attempts are made to resume that world, by name, either from the latest backup if it exists 
# or by determining the current world data is that world 
# 
# due to how world data is volumed into the server container (both for java and bedrock, the environment WORLD_NAME 
# sets the actual mount point of world data, and so world data on the volume is technically _unnamed_ until the server 
# is deployed), we must include some metadata in the volumed folder to track which world is currently loaded. 
# if the provided -w WORLD_NAME matches, we use the data in-place 
# otherwise, we attempt to retrieve world data from a backup
# if a backup does not exist, we clear the folder and allow the server to generate a new world
# if no -w WORLD_NAME is provided, whatever world name configured in the server environment along with world data present under that name are used
# given the world name on the volume metadata matches. if the metadata name does not match, or if no world data is present, as in the case where 
# -w WORLD_NAME is provided, backups are checked to see if one exists, and failing all these attempts, the environment world name is intercepted 
# and changed to a generic timestamp-based name to avoid a possible actual world with (lost/unreachable) backup history from being "reborn"

set -e 
 
. common 
. .env 

export TYPE 
export VOLUME_BASE 
export WORLD_BASE
export IMAGE 

# while read LINE; do 
#   IFS== read -ra PARTS < <(echo $LINE)
#   # -- break up by key/value to preserve quoted values with spaces 
#   EXPORT=$(echo "export ${PARTS[0]}=${PARTS[1]}")
#   echo "${EXPORT}"
#   eval ${EXPORT}
# done < <(cat .env | grep -vE "^#")

export SPEC_VERSION
export SPEC_WORLD_NAME
export SPEC_BACKUP_FILE 

FORCE_WORLD_DATA_WRITE=0
LEVELNAME_FILE=levelname.txt

###########################################
#
#   parameter collection 
#

ACTION=$1 
shift 

while [[ $# -gt 0 ]]; do 
  case $1 in 
    -v)     SPEC_VERSION=$2
            shift; shift 
            ;;
    -w)     SPEC_WORLD_NAME=$2
            shift; shift
            ;;
    -f)     FORCE_WORLD_DATA_WRITE=1
            shift
            ;;
    -b)     SPEC_BACKUP_FILE="$2"
            shift; shift 
            ;;
    *)      echo "$1 is not recognized as a command-line argument" && exit 1
            ;;
  esac 
done 

###########################################
#
#   validation
#

if [[ -n "${SPEC_BACKUP_FILE}" && -z "${SPEC_WORLD_NAME}" ]]; then 
  echo "If a backup file is provided, a world name must be specified."
  echo "This should be a distinct name or this world's true name, so subsequent backups of this world do not conflate with backups of another world"
  echo "CAUTION: if specifying an older backup, subsequent backups will create a historical branch"
  echo "In which case it would make sense to provide an appropriate name, e.g. myworld-alternate-from-<timestamp>"
  exit 1
fi 

if [[ -n "${SPEC_BACKUP_FILE}" ]]; then 
  echo "${SPEC_BACKUP_FILE} you say..?"
  
  if [[ "${SPEC_BACKUP_FILE}" =~ .*\.tar\.gz && ! -f "${SPEC_BACKUP_FILE}" ]]; then 
    echo "${SPEC_BACKUP_FILE} is an archive but doesn't exist"
    exit 1
  #elif [[ ! -d ${SPEC_BACKUP_FILE} ]]; then 
  #  echo "${SPEC_BACKUP_FILE} is a folder, but doesn't exist"
  #  exit 1
  fi 
fi 

if [[ -n "${SPEC_WORLD_NAME}" && -z "${SPEC_VERSION}" ]]; then 
  echo "World name was provided, so will not deploy for all versions."
  echo "Please pick one."
  exit 1
fi 

if [[ -n "${SPEC_VERSION}" ]]; then 
  echo "Specified version ${SPEC_VERSION}"
else 
  echo "Performing on all versions"
fi 

function _create_load_folder() {
  local WORK_FOLDER=_tmp_deploy_load_$(date +%Y%m%dT%H%M%S)
  mkdir -p ${WORK_FOLDER} 2>&1 > /dev/null && echo ${WORK_FOLDER}
}

function load() {

  local BACKUP_FILE=$1

  VERSIONED_WORLD_PATH=${VERSIONED_VOLUME_BASE}/world

  echo "Loading into minikube.."
  WORLD_FILES_CMD="find ${VERSIONED_WORLD_PATH} -type f"
  WORLD_FILES=$(target_platform_cmd "${WORLD_FILES_CMD}" | wc -l)

  if [[ ${WORLD_FILES} -gt 0 ]]; then 
    echo "There is world data loaded in ${VERSIONED_WORLD_PATH} already."
    echo -n "Do you want to destroy it permanently? y/N "
    read DESTROY
    if [[ "${DESTROY}" = "y" ]]; then
      echo "Okay, we're destroying ${VERSIONED_WORLD_PATH}.."
      DESTROY_CMD="sudo rm -rf ${VERSIONED_WORLD_PATH}/*"
      target_platform_cmd "${DESTROY_CMD}"
      echo "Destroyed!"
    else 
      echo "Leaving existing world data alone.."
      return 
    fi 
  else 
    echo "No world data found in ${VERSIONED_WORLD_PATH}, we're clear to deploy."
  fi 
  
  WORK_FOLDER=$(_create_load_folder) || return 

  # -- the following if we have a backup file tar.gz 
  if [[ "${BACKUP_FILE}" =~ tar.gz ]]; then 
    
    # -- look at WORLD_BASE to see the expected path/structure for backups made from it
    # -- will clue in the --strip-components # for unpacking the backup archive we have 
    IFS=/; read -ra BASEPARTS <<< "${WORLD_BASE}"; IFS=;
    STRIP=$(( ${#BASEPARTS[@]} ))
    echo "${STRIP} components stripping for ${WORLD_BASE}"  
  
    echo "Expanding ${BACKUP_FILE} --> ${WORK_FOLDER}"
    sudo tar -xzvf "${BACKUP_FILE}" -C ${WORK_FOLDER} --strip-components ${STRIP}

  else 

    echo "Copying ${BACKUP_FILE} as a world folder.."
    cp -anv ${BACKUP_FILE}/* ${WORK_FOLDER}

  fi 

  # -- after unpacking, make sure the world folder has the correct levelname file 
  # -- if it doesn't match WORLD_NAME, that's weird 
  # -- but otherwise, see a matching value or create it if missing 
  if [[ -f "${WORK_FOLDER}/${LEVELNAME_FILE}" ]]; then 
    LEVELNAME_CONTENTS=$(cat "${WORK_FOLDER}/${LEVELNAME_FILE}")
    if [[ "${LEVELNAME_CONTENTS}" != "${WORLD_NAME}" ]]; then 
      echo "*****"
      echo "*"
      echo "*    WHAT!?!? Replacing incorrect (${LEVELNAME_CONTENTS}) ${LEVELNAME_FILE}"
      echo "*"
      echo "*****"
      mv ${WORK_FOLDER}/${LEVELNAME_FILE} ${WORK_FOLDER}/${LEVELNAME_FILE}.bak
      printf "${WORLD_NAME}" > "${WORK_FOLDER}/${LEVELNAME_FILE}"
    else 
      echo "${WORLD_NAME} found as ${LEVELNAME_FILE}"
    fi     
  else 
    echo "Creating ${WORLD_NAME} as ${LEVELNAME_FILE}"
    printf "${WORLD_NAME}" > "${WORK_FOLDER}/${LEVELNAME_FILE}"
  fi 
  
  sudo chown -R ${USER}:${USER} ${WORK_FOLDER}
  
  echo "Copying ${BACKUP_FILE} --> ${WORK_FOLDER} --> minikube:${VERSIONED_WORLD_PATH}"
  docker cp "${WORK_FOLDER}" minikube:"${VERSIONED_WORLD_PATH}"

  echo "Moving ${VERSIONED_WORLD_PATH}/${WORK_FOLDER}/* --> ${VERSIONED_WORLD_PATH}"
  
  echo "move world data up to ${VERSIONED_WORLD_PATH}, out of transmission folder ${WORK_FOLDER}"
  target_platform_cmd "sudo mv -nv ${VERSIONED_WORLD_PATH}/${WORK_FOLDER}/* ${VERSIONED_WORLD_PATH}"
  echo "remove now-empty transmission folder ${VERSIONED_WORLD_PATH}/${WORK_FOLDER}"
  target_platform_cmd "sudo rm -rvf ${VERSIONED_WORLD_PATH}/${WORK_FOLDER}"
  echo "remove session.lock ${VERSIONED_WORLD_PATH}/session.lock"
  target_platform_cmd "sudo rm -vf ${VERSIONED_WORLD_PATH}/session.lock"
  echo "remove local work folder ${WORK_FOLDER}"
  rm -rf ${WORK_FOLDER}
  
  target_platform_cmd "sudo chown -R 999:999 ${VERSIONED_WORLD_PATH}"
  echo "${BACKUP_FILE} is loaded into (${TARGET_PLATFORM}) ${VERSIONED_WORLD_PATH}"

  ./envmanager update -v ${VERSION} -w "${WORLD_NAME}"
}

function clear_crontab_backup() {

  echo "Removing crontab: ${CRONTAB_TITLE}"
  # crontab -l | awk "/^# ${CRONTAB_TITLE}$/{c=2;next} !(c&&c--)" | crontab -  
  crontab -l | sed "/# ${CRONTAB_TITLE}/,+1d" | crontab -
}

function get_crontab_cmd() {
  [[ -z "${VERSION}" || -z "${WORLD_NAME}" || -z "${BACKUP_CP_CMD}" || ! -f ${PWD}/cron ]] \
    && echo "Crontab command cannot be generated (VERSION=${VERSION} WORLD_NAME=${WORLD_NAME} BACKUP_CP_CMD=${BACKUP_CP_CMD} or ${PWD}/cron DNE)" \
    && return 1
  echo "VERSION=${VERSION} WORLD_NAME=\"${WORLD_NAME}\" BACKUP_CP_CMD=\"${BACKUP_CP_CMD}\" ${PWD}/cron"
}

function add_crontab_backup() {

  echo "Adding crontab: ${CRONTAB_TITLE}"
  CRONTAB_CMD=$(get_crontab_cmd) || return $?

  printf "$(crontab -l) \n\
# ${CRONTAB_TITLE} \n\
*/15 * * * * ${CRONTAB_CMD} \n\
" | crontab -
}

# function add_crontab_minikube_backup() {

#   # -- docker cp must copy the whole folder, wildcards no happy  
#   # -- notice the docker target does the same thing for parity
#   printf "$(crontab -l) \n\
# # ${CRONTAB_TITLE} \n\
# #*/15 * * * * docker cp \"minikube:${VERSIONED_VOLUME_BASE}/backups/${WORLD_NAME}\" \"${PWD}/backups/${VERSION}/\" \n\
# " | crontab -

# }

# function add_crontab_docker_backup() {

#   printf "$(crontab -l) \n\
# # ${CRONTAB_TITLE} \n\
# */15 * * * * cp -anv \"${VERSIONED_VOLUME_BASE}/backups/${WORLD_NAME}\" \"${PWD}/backups/${VERSION}/\" \n\
# " | crontab -

# }

function up() {

  #############################
  #
  # volumes 
  # 

  # -- create the "local path" folders for the PersistentVolume resources
  for VOLUME in world backups log; do 
    echo "Making ${VERSIONED_VOLUME_BASE}/${VOLUME}"
    target_platform_cmd "mkdir -p ${VERSIONED_VOLUME_BASE}/${VOLUME}"
    target_platform_cmd "sudo chown -R 999:999 ${VERSIONED_VOLUME_BASE}/${VOLUME}"
  done 

  PATH_TO_LEVELNAME_FILE="${VERSIONED_VOLUME_BASE}/world/${LEVELNAME_FILE}"
  
  if [[ "${TARGET_PLATFORM}" = "minikube" ]]; then 

    #############################
    #
    #     volumes: minikube
    # 
      
    # -- create the "local path" folders for the PersistentVolume resources
    # for VOLUME in world backups; do 
    #   echo "Making ${VERSIONED_VOLUME_BASE}/${VOLUME}"
    #   minikube ssh "mkdir -p ${VERSIONED_VOLUME_BASE}/${VOLUME}"
    #   minikube ssh "sudo chown -R 999:999 ${VERSIONED_VOLUME_BASE}/${VOLUME}"
    # done 

    echo "Creating volumes.."
    YAML=$(cat ../templates/volumes.yaml | envsubst)
    if [[ ${SHOW_TEMPLATES} -eq 1 ]]; then 
      echo "${YAML}"
    fi 
    echo "${YAML}" | kubectl apply -f -

    # PATH_TO_LEVELNAME_FILE="minecraft/${TYPE}/volumes-${VERSION}/world/${LEVELNAME_FILE}"

    WORLD_DATA_PRESENT=$(minikube ssh "[[ \$(find ${VERSIONED_VOLUME_BASE}/world/level.dat 2>/dev/null) ]] && echo -n \"yes\" || echo -n \"no\"")
    # FOUND_WORLD=$(minikube ssh "cat ${PATH_TO_LEVELNAME_FILE} 2>/dev/null" 2>/dev/null || echo "")
    
  elif [[ "${TARGET_PLATFORM}" = "docker" ]]; then 

    #############################
    #
    #     volumes: docker
    # 
    
    # for VOLUME in backups log world; do 
    #   echo "Making ${VERSIONED_VOLUME_BASE}/${VOLUME}"
    #   mkdir -vp ${VERSIONED_VOLUME_BASE}/${VOLUME}
    # done 

    # PATH_TO_LEVELNAME_FILE="${VERSIONED_VOLUME_BASE}/world/${LEVELNAME_FILE}"

    WORLD_DATA_PRESENT=$([[ $(find ${VERSIONED_VOLUME_BASE}/world/level.dat 2>/dev/null) ]] && echo -n "yes" || echo -n "no")
    # FOUND_WORLD=$(cat ${PATH_TO_LEVELNAME_FILE} 2>/dev/null || echo "")

  fi 

  FOUND_WORLD=$(target_platform_cmd "cat ${PATH_TO_LEVELNAME_FILE} 2>/dev/null" 2>/dev/null || echo "")

  # -- if world data and found world matches WORLD_NAME, leave it be
  # -- this would be a simple server restart / redeployment 
  # -- if no world data or found world doesn't match WORLD_NAME, find a backup for WORLD_NAME
  # -- we can look in ${PWD}/backups/${VERSION}/${WORLD_NAME}
  # -- this would be a minikube restart, or deploying a different world in place of an existing deployment 
  # -- if a backup is needed and not found, let it be blank
  # -- this would be deploying a new world name
  

  if [[ ${FORCE_WORLD_DATA_WRITE} -eq 0 && "${WORLD_DATA_PRESENT}" = "yes" && -n "${FOUND_WORLD}" && "${FOUND_WORLD}" = "${WORLD_NAME}" ]]; then     
    echo "World data found, and it matches the environment (FORCE_WORLD_DATA_WRITE=${FORCE_WORLD_DATA_WRITE} WORLD_DATA_PRESENT=${WORLD_DATA_PRESENT} FOUND_WORLD=${FOUND_WORLD} WORLD_NAME=${WORLD_NAME})"
  elif [[ ${FORCE_WORLD_DATA_WRITE} -eq 1 || ("${WORLD_DATA_PRESENT}" = "no" || (-n "${FOUND_WORLD}" && "${FOUND_WORLD}" != "${WORLD_NAME}")) ]]; then 
    echo "World data not found, or the found world name doesn't match the environment, or we're forcing deployment (FORCE_WORLD_DATA_WRITE=${FORCE_WORLD_DATA_WRITE} WORLD_DATA_PRESENT=${WORLD_DATA_PRESENT} FOUND_WORLD=${FOUND_WORLD} WORLD_NAME=${WORLD_NAME})"
    if [[ -n "${SPEC_BACKUP_FILE}" ]]; then 
      echo "Using specified backup ${SPEC_BACKUP_FILE}"
      BACKUP_TO_LOAD="${SPEC_BACKUP_FILE}"
    else 
      echo "Searching for a recent backup of ${WORLD_NAME} in backups/${VERSION}/${WORLD_NAME}"
      BACKUP_TO_LOAD=$(find "${PWD}/backups/${VERSION}/${WORLD_NAME}" -name "*.tar.gz" -type f 2>/dev/null | sort -n -r | head -n 1)
    fi 
    if [[ -z "${BACKUP_TO_LOAD}" ]]; then 
      echo "A backup could not be found (VERSION=${VERSION}, WORLD_NAME=${WORLD_NAME})"
    else
      echo "Loading backup ${BACKUP_TO_LOAD}"
      load "${BACKUP_TO_LOAD}"
    fi 
  elif [[ "${WORLD_DATA_PRESENT}" = "yes" && -z "${FOUND_WORLD}" ]]; then 
    echo "World data found, but no ${LEVELNAME_FILE} level name file was found. This should be corrected - but has it changed?"
    echo "If it hasn't changed (-w had no effect on the value found in .jenv), we can make a reasonable assumption that this"
    echo "value is what it was when this current world data was placed or generated."
    echo "If it has changed (-w made the value in .jenv something different), we can make a reasonable assumption that the original"
    echo "value is what it was when this current world data was placed or generated."
    if [[ "${ORIGINAL_WORLD_NAME}" = "${WORLD_NAME}" ]]; then 
      echo "No, it hasn't. Guessing \"${WORLD_NAME}\" and writing to ${PATH_TO_LEVELNAME_FILE}"      
      WORLD_NAME_TO_WRITE="${WORLD_NAME}"
    else 
      echo "Yes, it has! Guessing the original value ${ORIGINAL_WORLD_NAME} and writing to ${PATH_TO_LEVELNAME_FILE}"
      WORLD_NAME_TO_WRITE="${ORIGINAL_WORLD_NAME}"      
    fi 

    echo "Creating ${PATH_TO_LEVELNAME_FILE}"
    target_platform_cmd "sudo touch ${PATH_TO_LEVELNAME_FILE}"
    echo "Permissioning ${PATH_TO_LEVELNAME_FILE}"
    target_platform_cmd "sudo chmod 664 ${PATH_TO_LEVELNAME_FILE}"
    echo "Writing level name to ${PATH_TO_LEVELNAME_FILE}"
    target_platform_cmd "echo -n ${WORLD_NAME_TO_WRITE} > ${PATH_TO_LEVELNAME_FILE}"
  else 
    echo "No expected convergence of state was observed (FORCE_WORLD_DATA_WRITE=${FORCE_WORLD_DATA_WRITE} WORLD_DATA_PRESENT=${WORLD_DATA_PRESENT} FOUND_WORLD=${FOUND_WORLD} WORLD_NAME=${WORLD_NAME})"
  fi 

  #############################3
  #
  # environment
  # 

  PATCH_ENVIRONMENT=(VERSION WORLD_NAME GAMEMODE MOTD)

  if [[ "${TARGET_PLATFORM}" = "minikube" ]]; then 

    echo "Deleting and re-creating ${IMAGE}-${VERSION} configmap from .env.."
    (kubectl get configmap ${IMAGE}-${VERSION} >/dev/null 2>&1 && kubectl delete configmap ${IMAGE}-${VERSION} || true) \
      && kubectl create configmap --from-env-file=.env ${IMAGE}-${VERSION}
    
    if [[ "${VERSION}" = "1.16.5" ]]; then 
      kubectl patch configmap ${IMAGE}-${VERSION} --patch "{\"data\": {\"JAVA_CONF\": \"-Dlog4j2.configurationFile=patch/log4j2112116.xml\"}}"
    fi 

    for PATCH_ENV in ${PATCH_ENVIRONMENT[@]}; do 
      kubectl patch configmap ${IMAGE}-${VERSION} --patch "{\"data\": {\"${PATCH_ENV}\": \"${!PATCH_ENV}\"}}"
    done 

    # kubectl patch configmap ${IMAGE}-${VERSION} --patch "{\"data\": {\"VERSION\": \"${VERSION}\"}}"
    # kubectl patch configmap ${IMAGE}-${VERSION} --patch "{\"data\": {\"WORLD_NAME\": \"${WORLD_NAME}\"}}"
    # kubectl patch configmap ${IMAGE}-${VERSION} --patch "{\"data\": {\"GAMEMODE\": \"${GAMEMODE}\"}}"
    # kubectl patch configmap ${IMAGE}-${VERSION} --patch "{\"data\": {\"MOTD\": \"${MOTD}\"}}"
  
  elif [[ "${TARGET_PLATFORM}" = "docker" ]]; then 

    echo "Please modify docker-compose.yml to include the following as `environment`:"
    echo "    - ${PATCH_ENV}=\${${PATCH_ENV}}"
    
  fi 

  #############################3
  #
  # deployment
  # 

  if [[ "${TARGET_PLATFORM}" = "minikube" ]]; then 
    
    echo "Creating ${IMAGE}-${VERSION} deployment, and services.."
    YAML=$(cat templates/minecraft.yaml | envsubst)
    if [[ ${SHOW_TEMPLATES} -eq 1 ]]; then 
      echo "${YAML}"
    fi 
    echo "${YAML}" | kubectl apply -f -
    
    kubectl rollout restart deployment ${IMAGE}-${VERSION}
    
    SERVICE_NAME="${IMAGE}-service-${VERSION_HYPHEN}"

    DEPLOY_SERVICES=$(minikube service list | grep ${SERVICE_NAME} -A 1 | grep -v mcrcon)

    export MINIKUBE_URL_CODE
    DEPLOY_MINIKUBE_URL=$([[ ${DEPLOY_SERVICES} =~ [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:([0-9]{5}) ]] \
      && echo ${BASH_REMATCH[0]} \
      && MINIKUBE_URL_CODE=$? \
      || (MINIKUBE_URL_CODE=$? && echo "")
    )

    echo "/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"
    echo "**"
    echo "**"
    echo "** -=-=-=-=-     ${TYPE} ${VERSION} Minikube container URL    -=-=-=-=-=-"
    echo "**"
    if [[ ${MINIKUBE_URL_CODE} -eq 0 ]]; then 
      echo "**          ----->    http://${DEPLOY_MINIKUBE_URL}   <-----"
    else 
      echo "**                 (URL match statement failed, sorry!)"
    fi 
    echo "**"
    echo "**"
    echo "/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"

  elif [[ "${TARGET_PLATFORM}" = "docker" ]]; then 

    docker-compose up --force-recreate -d $@

  fi 

  #############################3
  #
  # pull and prune backups
  # 

  [[ ! -d ${PWD}/backups/${VERSION}/${WORLD_NAME} ]] && mkdir -pv ${PWD}/backups/${VERSION}/${WORLD_NAME}
  
  clear_crontab_backup
  add_crontab_backup || return $?
}

function down() {

  #############################3
  #
  # deployment cleanup 
  # 

  if [[ "${TARGET_PLATFORM}" = "minikube" ]]; then 

    echo "Deleting configmap.."
    cat templates/minecraft_env.yaml | envsubst | kubectl delete -f - || echo "Env delete failed"
    echo "Deleting volumes, deployment, and services.."
    cat templates/minecraft.yaml | envsubst | kubectl delete -f - || echo "Deployment delete failed"
  
  elif [[ "${TARGET_PLATFORM}" = "docker" ]]; then 

    docker-compose down 

  fi 

  #############################3
  #
  # backup cron cleanup
  # 

  clear_crontab_backup


  
  echo "Copying the last of the backups:"
  echo "${BACKUP_CP_CMD} --> ${PWD}/backups/${VERSION}"

  ${BACKUP_CP_CMD} ${PWD}/backups/${VERSION}/ || echo "Last backup copy failed"
  # docker cp "minikube:${VERSIONED_VOLUME_BASE}/backups/${WORLD_NAME}" "${PWD}/backups/${VERSION}/" || echo "Last backup copy failed"
}

function list() {

  docker-compose ps 
}

for VERSION in ${VERSION_ARRAY[@]}; do 
  
  export VERSION 

  if [[ -n "${SPEC_VERSION}" && "${VERSION}" != "${SPEC_VERSION}" ]]; then 
    continue 
  fi 

  export WORLD_NAME="$(version_parameter world_name)"
  export GAMEMODE=$(version_parameter gamemode)
  export TARGET_PLATFORM=$(version_parameter target_platform)
  export CRONTAB_TITLE="${IMAGE}-${VERSION} ${TARGET_PLATFORM} world volume backup"
  

  # export WORLD_NAME=$(cat .jenv | jq -r ".worlds | .[] | select(.version == \"${VERSION}\") | .world_name")
  # export GAMEMODE=$(cat .jenv | jq -r ".worlds | .[] | select(.version == \"${VERSION}\") | .gamemode")
  # export TARGET_PLATFORM=$(cat .jenv | jq -r ".worlds | .[] | select(.version == \"${VERSION}\") | .target_platform")

  export ORIGINAL_WORLD_NAME=${WORLD_NAME}

  if [[ -n "${SPEC_WORLD_NAME}" && "${SPEC_WORLD_NAME}" != "${WORLD_NAME}" ]]; then 
    echo "Provided world name \"${SPEC_WORLD_NAME}\" is different than world name in config \"${WORLD_NAME}\""
    echo "Config will be updated to ${SPEC_WORLD_NAME} when the world data is put in place"
    # -- the configured environment in .jenv should be changed atomically with world data changing on disk
    # -- so we only collect the name here, and we'll set it later 
    WORLD_NAME="${SPEC_WORLD_NAME}"
  fi   

  if [[ -z "${WORLD_NAME}" ]]; then 
    echo "WORLD_NAME cannot be empty, but it is"
    echo "Check .jenv"
    exit 1
  fi 

  echo "Using world name: ${WORLD_NAME}"
  
  export MOTD="${WORLD_NAME}-${VERSION}"
  # -- change dots to hyphens for k8s standard domain naming, apparently only a problem for Service 
  export VERSION_HYPHEN=${VERSION//./-}
  
  if [[ "${TARGET_PLATFORM}" = "docker" ]]; then 
    VOLUME_BASE=${PWD}/live/volumes    
  fi 

  export VERSIONED_VOLUME_BASE=${VOLUME_BASE}-${VERSION}

  if [[ "${TARGET_PLATFORM}" = "minikube" ]]; then 
    export BACKUP_CP_CMD="docker cp minikube:${VERSIONED_VOLUME_BASE}/backups/${WORLD_NAME}"
  elif [[ "${TARGET_PLATFORM}" = "docker" ]]; then 
    export BACKUP_CP_CMD="cp -anv \"${VERSIONED_VOLUME_BASE}/backups/${WORLD_NAME}\""
  fi

  if [[ "${ACTION}" = "up" ]]; then 
    up
  elif [[ "${ACTION}" = "down" ]]; then 
    down || (echo "Deploy teardown failed ${ERRORMSG}")
  fi 

done 
