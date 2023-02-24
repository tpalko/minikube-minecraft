#!/bin/bash

echo "Welcome to backup.sh!"

# set -e 

# -- WORLD_NAME originates from an .env file which must double-quote values with spaces 
# -- in the pod, .env is represented by a ConfigMap, which again wraps values in double quotes
# -- and so the original double quotes become part of the value, not functional encapsulating syntax 
export WORLD_NAME=$(echo ${WORLD_NAME} | sed "s/\"//g")

BACKUPS_WORLD_FOLDER=${BACKUPS_WORLD_FOLDER:="/opt/minecraft/backups/${WORLD_NAME}"}

BACKUP_PERIOD_MIN_DEFAULT=15
BACKUP_PERIOD_MIN=${BACKUP_PERIOD_MIN:=${BACKUP_PERIOD_MIN_DEFAULT}}
TMP_FOLDER=_tmp 
PRUNE_DIFF_CURSOR_FILE=.prune-diff-cursor
BACKUP_RETENTION_WINDOW=1
BACKUP_EXPIRATION_DAYS=7

function rcon {
  if [[ -f /opt/minecraft/tools/mcrcon/mcrcon ]]; then 
    CMD=$1
    /opt/minecraft/tools/mcrcon/mcrcon -H 127.0.0.1 -P 25575 -p ${RCON_PASSWORD} "${CMD}"
  else 
    echo "no mcrcon"
  fi 
}

function work_folder_for_archive() {
  ARCHIVE="$1"
  [[ ${ARCHIVE} =~ [\.\]?/(.+)".tar.gz" ]] && echo ${TMP_FOLDER}/${BASH_REMATCH[1]}
}

function compare_files() {
  # -- for DIFF to remain zero after this
  # -- either both files are present and hash equal
  # -- or both files are missing 
  FIRST_FILE="$1"
  SECOND_FILE="$2"
  echo "Comparing"
  echo "${FIRST_FILE}"
  echo "${SECOND_FILE}"
  if [[ -n "${FIRST_FILE}" && -n "${SECOND_FILE}" ]]; then 
    FIRST_FILE_SHA=$(shasum ${FIRST_FILE} | awk '{ print $1 }')
    SECOND_FILE_SHA=$(shasum ${SECOND_FILE} | awk '{ print $1 }')
    if [[ "${FIRST_FILE_SHA}" != "${SECOND_FILE_SHA}" ]]; then 
      DIFF=1
    else 
      echo "The files are the same"
    fi 
  elif [[ -z "${FIRST_FILE}" && -z "${SECOND_FILE}" ]]; then 
    echo "Both files are missing"
  elif [[ -z "${FIRST_FILE}" || -z "${SECOND_FILE}" ]]; then 
    DIFF=1
  fi 
}

function expand_to_temp() {
  BACKUPFILE="$1"  
  WORK_FOLDER="$2"
  echo "Expanding ${BACKUPFILE} to ${WORK_FOLDER}"
  echo "Creating work folder ${WORK_FOLDER}"
  mkdir -vp ${WORK_FOLDER}
  echo "${BACKUPFILE}:"  
  tar --skip-old-files -xzvf ${BACKUPFILE} -C ${WORK_FOLDER} --strip-components 4
}

function cleanup_temp() {
  WORK_FOLDER="$1"
  echo "Cleaning up work folder ${WORK_FOLDER}"
  rm -rvf ${WORK_FOLDER}      
}

function prune_log() {
  MSG="$1"
  echo "${MSG}" | tee -a ${PRUNE_LOG}
}

function json_diff_stats_folder() {

  FIRST_WORK_FOLDER="$1"
  SECOND_WORK_FOLDER="$2"

  prune_log "JSON diffing ${FIRST_WORK_FOLDER} -> ${SECOND_WORK_FOLDER}"

  while read STATSFILE; do 
        
    STATSFILEBASENAME=$(basename ${STATSFILE})
    prune_log "Looking for ${STATSFILEBASENAME} in ${SECOND_WORK_FOLDER}"
    OTHERSTATSFILE=$(find ${SECOND_WORK_FOLDER} -name "${STATSFILEBASENAME}")

    if [[ -n "${OTHERSTATSFILE}" ]]; then           
      
      cat ${STATSFILE} | jq > _tmpone.json \
        && cat ${OTHERSTATSFILE} | jq > _tmptwo.json  \
        && JSON_DIFF="$(diff -w _tmpone.json _tmptwo.json)" \
        && (
          prune_log "${STATSFILEBASENAME} diff ${FIRST_WORK_FOLDER} <-> ${SECOND_WORK_FOLDER}" \
          && prune_log " v v v v v " \
          && prune_log "${JSON_DIFF}" \
          && prune_log " ^ ^ ^ ^ ^ "
        ) \
        || prune_log "JSON diff failed"

      rm -vf _tmpone.json _tmptwo.json 

    else 
      prune_log "${STATSFILE} from ${FIRST_WORK_FOLDER} was not found in ${SECOND_WORK_FOLDER}"
    fi 

  done < <(find ${FIRST_WORK_FOLDER}/stats/*.json)
}

function prune_duplicates() {

  while :; do 

    # -- investigation 
    
    NEWER=
    LATER_THAN_FILE=
    if [[ -f ${PRUNE_DIFF_CURSOR_FILE} ]]; then 
      LATER_THAN_FILE=$(cat ${PRUNE_DIFF_CURSOR_FILE})
      if [[ -f ${LATER_THAN_FILE} ]]; then 
        NEWER=" -newer ${LATER_THAN_FILE} "
      else 
        echo "Later-than file ${LATER_THAN_FILE} does not exist!"
        unset LATER_THAN_FILE
      fi 
    fi     

    ALL_BACKUPS=$(find . -type f ${NEWER} -wholename "./*.tar.gz" | sort -n)
    BACKUP_COUNT=$(echo "${ALL_BACKUPS}" | wc -l)

    prune_log "    /./././././././././\.\.\.\.\.\.\.\.\.\.\  "
    prune_log "    /.                                    .\  "
    prune_log "    /.  ${BACKUP_COUNT} total backups"
    prune_log "    /.   newer: ${LATER_THAN_FILE}"
    prune_log "    /.                                 "
    # prune_log "    /.       last two of ${TAKE}       "
    prune_log "    /.                                 "

    if [[ ${BACKUP_COUNT} -lt 2 ]]; then 
      prune_log "Not enough backups to compare (${BACKUP_COUNT}), quitting"
      break 
    fi 

    # -- selection 

    TWO_EARLIEST=$(echo "${ALL_BACKUPS}" | head -n 2)
    FIRST=$(echo "${TWO_EARLIEST}" | head -n 1)
    SECOND=$(echo "${TWO_EARLIEST}" | tail -n 1)

    prune_log "Selected the next two for comparison:"
    prune_log "First:  ${FIRST}"
    prune_log "Second: ${SECOND}"

    if [[ "${FIRST}" = "${SECOND}" ]]; then 
      prune_log "The two files to compare look the same.. we can probably stop now"
      break 
    fi 

    # -- setup 

    FIRST_WORK_FOLDER=$(work_folder_for_archive "${FIRST}")
    SECOND_WORK_FOLDER=$(work_folder_for_archive "${SECOND}")

    expand_to_temp "${FIRST}" "${FIRST_WORK_FOLDER}" \
      || (prune_log "Ooops! What happened?" && cleanup_temp "${FIRST_WORK_FOLDER}" && mv -nv "${FIRST}" ${BACKUPS_WORLD_FOLDER}/broken && continue)

    expand_to_temp "${SECOND}" "${SECOND_WORK_FOLDER}" \
      || (prune_log "Ooops! What happened?" && cleanup_temp "${FIRST_WORK_FOLDER}" && cleanup_temp "${SECOND_WORK_FOLDER}" && mv "${SECOND}" ${BACKUPS_WORLD_FOLDER}/broken && continue)
    
    PLAYERDATA_FOLDER_DIFF=$(diff -rwa "${FIRST_WORK_FOLDER}/playerdata" "${SECOND_WORK_FOLDER}/playerdata" 2>&1)
    PLAYERDATA_FOLDER_DIFF_CODE=$?
    STATS_FOLDER_DIFF=$(diff -rwa "${FIRST_WORK_FOLDER}/stats" "${SECOND_WORK_FOLDER}/stats" 2>&1)
    STATS_FOLDER_DIFF_CODE=$?

    if [[ ${PLAYERDATA_FOLDER_DIFF_CODE} -eq 0 && ${STATS_FOLDER_DIFF_CODE} -eq 0 ]]; then 
    
      prune_log "All playerdata and stats files are identical"
      mv -nv ${SECOND} ${BACKUPS_WORLD_FOLDER}/pruned  

    else 

      if [[ ${PLAYERDATA_FOLDER_DIFF_CODE} -lt 2 && ${STATS_FOLDER_DIFF_CODE} -lt 2 ]]; then 
        prune_log "Some difference in playerdata or stats files"        
      else 
        prune_log "Errors occurred comparing playerdata (${PLAYERDATA_FOLDER_DIFF_CODE}) or stats (${STATS_FOLDER_DIFF_CODE}) files"
      fi 

      echo "playerdata:"
      echo " v v v v v "
      echo "${PLAYERDATA_FOLDER_DIFF}"
      echo " ^ ^ ^ ^ ^ "
      echo "stats:"
      echo " v v v v v "
      echo "${STATS_FOLDER_DIFF}"
      echo " ^ ^ ^ ^ ^ "      

      if [[${STATS_FOLDER_DIFF_CODE} -eq 1 ]]; then 
        prune_log "Stats diff is 1, looking more closely.."
        json_diff_stats_folder "${FIRST_WORK_FOLDER}" "${SECOND_WORK_FOLDER}"
        json_diff_stats_folder "${SECOND_WORK_FOLDER}" "${FIRST_WORK_FOLDER}"
      else 
        prune_log "Stats diff is 0"
      fi 

      echo -n ${FIRST} > ${PRUNE_DIFF_CURSOR_FILE}
    fi 

    # -- cleanup 

    prune_log "Cleaning up ${FIRST}"
    cleanup_temp "${FIRST_WORK_FOLDER}"

    prune_log "Cleaning up ${SECOND}"
    cleanup_temp "${SECOND_WORK_FOLDER}"

  done
}

function prune_expired() {
  while :; do 
    BACKUPS_IN_WINDOW=$(find . -mtime -${BACKUP_RETENTION_WINDOW} -wholename "./*.tar.gz" | wc -l)  
    echo "Backup retention window: ${BACKUP_RETENTION_WINDOW} -- Backups: ${BACKUPS_IN_WINDOW}"
    if [[ ${BACKUPS_IN_WINDOW} -gt 5 ]]; then 
      echo "This is good enough!"
      if [[ ${BACKUP_RETENTION_WINDOW} > ${BACKUP_EXPIRATION_DAYS} ]]; then 
        echo "We had to go out ${BACKUP_RETENTION_WINDOW} to collect enough backups, so bumping expiration to there"
        BACKUP_EXPIRATION_DAYS=${BACKUP_RETENTION_WINDOW}
      fi 
      EXPIRED_BACKUPS=$(find . -mtime +${BACKUP_EXPIRATION_DAYS} -wholename "./*.tar.gz" | wc -l)
      echo "${EXPIRED_BACKUPS} expired backups going out ${BACKUP_EXPIRATION_DAYS} days"
      find . -mtime +${BACKUP_EXPIRATION_DAYS} -wholename "./*.tar.gz" | mv -anv -t ${BACKUPS_WORLD_FOLDER}/expired
      break 
    fi 
    if [[ ${BACKUP_RETENTION_WINDOW} -gte 30 ]]; then 
      echo "No backups for 30 days? We aren't deleting anything."
      break 
    fi 
    BACKUP_RETENTION_WINDOW=$(( ${BACKUP_RETENTION_WINDOW} + 1 ))
  done 
}

function prune_backups() {

  PRUNE_LOG=/opt/minecraft/log/prune_${RUN_TIMESTAMP}.log
  
  prune_log "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
  prune_log "-=- "
  prune_log "-=-       Pruning starting $(date)"
  prune_log "-=- "

  pushd ${BACKUPS_WORLD_FOLDER}

  mkdir -p ${BACKUPS_WORLD_FOLDER}/{pruned,broken,expired}  
  
  prune_duplicates

  prune_log "Cleaning out pruned folder.."
  rm -vf ${BACKUPS_WORLD_FOLDER}/pruned/*

  prune_expired
  
  prune_log "Cleaning out expired folder.."
  rm -vf ${BACKUPS_WORLD_FOLDER}/expired/*

  popd 
  
  prune_log "-=- "
  prune_log "-=-       Pruning finished $(date)"
  prune_log "-=- "
  prune_log "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="

}

function backup() {

  echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
  echo "-=- "
  echo "-=-       Backup starting $(date)"
  echo "-=- "

  [[ -d "${BACKUPS_WORLD_FOLDER}" ]] || (echo "Creating ${BACKUPS_WORLD_FOLDER}.." && mkdir -p "${BACKUPS_WORLD_FOLDER}")

  rcon "save-off"
  rcon "save-all"
  tar -cvpzf "${BACKUPS_WORLD_FOLDER}/${WORLD_NAME}-world-${VERSION}-${RUN_TIMESTAMP}.tar.gz" "${WORLD_BASE}/${WORLD_NAME}"
  rcon "save-on"

  echo "-=- "
  echo "-=-       Backup finished $(date)"
  echo "-=- "
  echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
}

function schedule_backup() {

  echo "Initializing backup/prune loop"

  (while :; do     
    sleep $(( 60*${BACKUP_PERIOD_MIN} )) \
      && touch /opt/minecraft/log/backup.lock \
      && export RUN_TIMESTAMP=$(date +%F-%H-%M) \
      && (backup && prune_backups || echo "OH NO! something failed in the backup..") >> /opt/minecraft/log/backup.log 2>&1 \
      && rm -vf /opt/minecraft/log/backup.lock
  done) &
}

function fix_properties() {
  for ENTRY in ${ENTRIES[@]}; do 
    IFS==; read -ra PARTS <<< "${ENTRY}"
    echo ""
    echo "${ENTRY}"
    echo "Looking for ${PARTS[0]} as a field name in server.properties.."
    if ! grep -E "^${PARTS[0]}" server.properties 2>&1 >/dev/null; then 
      echo "Did not find. Adding ${PARTS[0]}=${PARTS[1]} to server.properties"
      printf "${PARTS[0]}=${PARTS[1]}\n" >> server.properties 
    else 
      echo "Found ${PARTS[0]} in server.properties:"
      grep -E "^${PARTS[0]}" server.properties
      echo "Fixing ---> ${PARTS[0]}=${PARTS[1]}"
      sed -i "s/^${PARTS[0]}=.*$/${PARTS[0]}=${PARTS[1]}/" server.properties 
      echo "${PARTS[0]} now in server.properties:"
      grep -E "^${PARTS[0]}" server.properties
    fi 
  done 

  echo "Final server.properties (${PWD}):"

  echo "v v v v v v v v"
  echo ""
  stat server.properties
  cat server.properties
  echo ""
  echo "^ ^ ^ ^ ^ ^ ^ ^"
}

echo "rcon and backup sourced"
