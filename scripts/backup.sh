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

function compare_folders() {
  FIRST_FOLDER="$1"
  SECOND_FOLDER="$2"
  FOLDER_DIFF=$(diff -r "${FIRST_FOLDER}" "${SECOND_FOLDER}")  
}

function compare_json_files() {
  FIRST_FILE="$1"
  SECOND_FILE="$2"
  echo "Comparing JSON"
  echo "${FIRST_FILE}"
  echo "${SECOND_FILE}"
  echo "Parsing ${FIRST_FILE} to JSON.."
  cat "${FIRST_FILE}" | jq > ${FIRST_FILE}.json
  PARSE_CODE=$?
  [[ ${PARSE_CODE} -ne 0 ]] && echo "Parsing ${FIRST_FILE} to JSON failed (${PARSE_CODE})" && return ${PARSE_CODE} 
  echo "Parsing ${SECOND_FILE} to JSON.."
  cat "${SECOND_FILE}" | jq > ${SECOND_FILE}.json
  PARSE_CODE=$?
  [[ ${PARSE_CODE} -ne 0 ]] && echo "Parsing ${SECOND_FILE} to JSON failed (${PARSE_CODE})" && return ${PARSE_CODE} 
  [[ ! -f "${FIRST_FILE}.json" || ! -f "${SECOND_FILE}.json" ]] && echo "Both formatted JSON files are not present" && return 1
  echo "Performing diff.."
  JSONDIFF=$(diff -w "${FIRST_FILE}.json" "${SECOND_FILE}.json" || echo "ok")
  echo "JSON diff calculated"
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

function prune_backups() {

  PRUNE_LOG=/opt/minecraft/log/prune_$(date +%F-%H-%M).log

  prune_log "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
  prune_log "-=- "
  prune_log "-=-       Pruning starting $(date)"
  prune_log "-=- "

  pushd ${BACKUPS_WORLD_FOLDER}

  # echo "Deleting older backups.."
  # for OLD in $(find . -type f -mtime +3 -name '*.gz'); do 
  #   rm -v ${OLD}
  # done 

  mkdir -p ${BACKUPS_WORLD_FOLDER}/{pruned,broken,expired}  

  TMP_FOLDER=_tmp 
  # TAKE=2
  
  while :; do 

    # -- investigation 
    
    NEWER=
    LATER_THAN_FILE=
    if [[ -f  ]]; then 
      LATER_THAN_FILE=$(cat )
      if [[ -f ${LATER_THAN_FILE} ]]; then 
        NEWER=" -newer ${LATER_THAN_FILE} "
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

    #if [[ ${TAKE} -gt ${BACKUP_COUNT} ]]; then 
    #  prune_log "We're at the end of the list, quitting"
    #  break 
    #fi 
    
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

      # TAKE=$(( ${TAKE} + 1 ))

      echo -n ${FIRST} > 
    fi 

    # -- SECOND ATTEMPT: get presumed single playerdata/stats file in each backup and compare each set 
    # FIRST_PLAYERDATA=($(find ${TMP_FOLDER}/${FIRST_WORK_FOLDER} -type f -wholename "*/playerdata/*" | grep -vE "old"))
    # SECOND_PLAYERDATA=($(find ${TMP_FOLDER}/${SECOND_WORK_FOLDER} -type f -wholename "*/playerdata/*" | grep -vE "old"))
    # FIRST_STATS=($(find ${TMP_FOLDER}/${FIRST_WORK_FOLDER} -type f -wholename "*/stats/*" | grep -vE "old|json\.json"))
    # SECOND_STATS=($(find ${TMP_FOLDER}/${SECOND_WORK_FOLDER} -type f -wholename "*/stats/*" | grep -vE "old|json\.json"))

    # if [[ ${#FIRST_PLAYERDATA[@]} -gt 1 \
    #       || ${#SECOND_PLAYERDATA[@]} -gt 1 \
    #       || ${#FIRST_STATS[@]} -gt 1 \
    #       || ${#SECOND_STATS[@]} -gt 1 ]]; then 

    #   echo "File selection picked up more than one file, comparison would be invalid"
    #   echo ""
    #   echo "FIRST_PLAYERDATA -->"
    #   echo "${FIRST_PLAYERDATA[@]}"
    #   echo ""
    #   echo "SECOND_PLAYERDATA -->"
    #   echo "${SECOND_PLAYERDATA[@]}"
    #   echo ""
    #   echo "FIRST_STATS -->"
    #   echo "${FIRST_STATS[@]}"
    #   echo ""
    #   echo "SECOND_STATS -->"
    #   echo "${SECOND_STATS[@]}"
    #   echo ""

    #   break 
    # fi 
    
    # FIRST_PLAYERDATA=${FIRST_PLAYERDATA[0]}
    # SECOND_PLAYERDATA=${SECOND_PLAYERDATA[0]}
    # FIRST_STATS=${FIRST_STATS[0]}
    # SECOND_STATS=${SECOND_STATS[0]}

    # echo "FIRST_PLAYERDATA -->  ${FIRST_PLAYERDATA}"
    # echo "SECOND_PLAYERDATA --> ${SECOND_PLAYERDATA}"
    # echo "FIRST_STATS -->       ${FIRST_STATS}"
    # echo "SECOND_STATS -->      ${SECOND_STATS}"

    # -- FIRST ATTEMPT: compare total and distinct counts, reducing by unique hashed contents, what?
    # PLAYERDATA_FILES=$(find ${TMP_FOLDER} -type f -wholename "*/playerdata/*" | grep -vE "old|pruned|broken")
    # STATS_FILES=$(find ${TMP_FOLDER} -type f -wholename "*/stats/*" | grep -vE "old|pruned|broken")

    # PLAYERDATA_UNDISTINCTS=$(echo "${PLAYERDATA_FILES}" | wc -l)
    # STATS_UNDISTINCTS=$(echo "${STATS_FILES}" | wc -l)

    # echo "playerdata files (${PLAYERDATA_UNDISTINCTS}):"
    # echo "${PLAYERDATA_FILES}"

    # echo "stats files (${STATS_UNDISTINCTS}):"
    # echo "${STATS_FILES}"

    # -- test 

    # -- FIRST ATTEMPT IMPROVEMENT: tighten up comparison logic
    # DIFF=0 

    # compare_files "${FIRST_PLAYERDATA}" "${SECOND_PLAYERDATA}"
    # compare_files "${FIRST_STATS}" "${SECOND_STATS}"
    # JSONDIFF=
    # compare_json_files "${FIRST_STATS}" "${SECOND_STATS}"
    # JSONDIFF_RESULT=$?

    # if [[ ${JSONDIFF_RESULT} -eq 0 ]]; then 
    #   echo "Stats diff:"
    #   echo "${JSONDIFF}"
    # else
    #   echo "${JSONDIFF}"
    # fi 

    # -- FIRST ATTEMPT: original comparison
    # PLAYERDATA_DISTINCTS=
    # STATS_DISTINCTS=

    # -- only if the total number of files is exactly 2 do we bother doing a comparison

    # if [[ ${PLAYERDATA_UNDISTINCTS} -ne 2 || ${STATS_UNDISTINCTS} -ne 2 ]]; then 
    #   echo "We don't have exactly two each playerdata and stats files.. something is wrong"
    # fi 

    # if [[ ${PLAYERDATA_UNDISTINCTS} -eq 2 ]]; then 
    #   PLAYERDATA_DISTINCTS=$(echo "${PLAYERDATA_FILES}" | xargs shasum | awk '{ print $1 }' | uniq | wc -l)
    # fi 

    # if [[ ${STATS_UNDISTINCTS} -eq 2 ]]; then 
    #   STATS_DISTINCTS=$(echo "${STATS_FILES}" | xargs shasum | awk '{ print $1 }' | uniq | wc -l)
    # fi

    # -- results 

    # if [[ ${DIFF} -eq 0 && (${JSONDIFF_RESULT} -eq 0 && -z "${JSONDIFF}") ]]; then 
    #   echo "All compared files resulted in no discerable difference -- chucking the second one"
    #   mv -nv ${SECOND} ${BACKUPS_WORLD_FOLDER}/pruned  
    # else 
    #   echo "Comparing files resulted in some difference -- keeping both "
    #   TAKE=$(( ${TAKE} + 1 ))
    #   echo "TAKE=${TAKE}"
    # fi 

    # echo "PLAYERDATA_DISTINCTS=${PLAYERDATA_DISTINCTS}"
    # echo "STATS_DISTINCTS=${STATS_DISTINCTS}"

    # if [[ -z "${PLAYERDATA_DISTINCTS}" || -z "${STATS_DISTINCTS}" ]]; then 
    #   echo "One or more distinct counts could not be determined."
    #   echo "Quitting for everybody's safety"
    #   QUIT=1
    # fi 

    # if [[ (${PLAYERDATA_UNDISTINCTS} -eq ${PLAYERDATA_DISTINCTS}) \
    #   && (${STATS_UNDISTINCTS} -eq ${STATS_DISTINCTS}) ]]; then 

    #     echo "Playerdata in ${FIRST} differs from playerdata in ${SECOND}"
    #     echo "AND"
    #     echo "Stats in ${FIRST} differs from stats in ${SECOND}"      
    #     echo "Let's keep both, and move onto the next two.."  
        

    # elif [[ (${PLAYERDATA_UNDISTINCTS} -eq 2 && ${PLAYERDATA_DISTINCTS} -eq 1) \
    #   && (${STATS_UNDISTINCTS} -eq 2 && ${STATS_DISTINCTS} -eq 1) ]]; then 

    #   echo "There are 2 playerdata and stats files each.. and they look the same.."
    #   echo "We can safely remove ${SECOND}.. it is redundant"
      
    
    # else 

    #   echo "Playerdata or stats counts were unexpected.. or were not found.."      
    #   echo "Quitting for everybody's safety"
    #   QUIT=1
      
    # fi  

    # -- cleanup 

    prune_log "Cleaning up ${FIRST}"
    cleanup_temp "${FIRST_WORK_FOLDER}"

    prune_log "Cleaning up ${SECOND}"
    cleanup_temp "${SECOND_WORK_FOLDER}"

  done

  prune_log "Cleaning out pruned folder.."
  rm -vf ${BACKUPS_WORLD_FOLDER}/pruned/*

  BACKUP_RETENTION_WINDOW=1
  BACKUP_EXPIRATION_DAYS=7

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
  tar -cvpzf "${BACKUPS_WORLD_FOLDER}/${WORLD_NAME}-world-${VERSION}-$(date +%F-%H-%M).tar.gz" "${WORLD_BASE}/${WORLD_NAME}"
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
