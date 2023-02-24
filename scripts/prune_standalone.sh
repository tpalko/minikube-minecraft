#!/bin/bash 

function usage() {
    echo "Usage: $0 -f BACKUP_FOLDER -v VERSION"
}

if [[ -n "${BACKUPS_WORLD_FOLDER}" && -d ${BACKUPS_WORLD_FOLDER} ]]; then

    . ./scripts/backup.sh 
    prune_backups
    exit $?

else 

    while [[ $# -gt 0 ]]; do 
        case $1 in 
            -f)     BACKUP_FOLDER=$2
                    shift; shift 
                    ;;
            -v)     VERSION=$2
                    shift; shift 
                    ;;
            *)      usage && exit 1
                    ;;
        esac 
    done 

    if [[ -z "${BACKUP_FOLDER}" || -z "${VERSION}" ]]; then 
        usage 
        exit 1
    fi 

    if [[ ! -d "${BACKUP_FOLDER}" ]]; then 
        echo "${BACKUP_FOLDER} doesn't exist"
        exit 1
    fi 

    if [[ ! -f .env ]]; then 
        echo "Run this script in the 'java' or 'bedrock' context folder"
        exit 1
    fi 

    export $(cat .env | xargs)
    # . ../scripts/minikube-env.sh 

    ./build -v ${VERSION} -c docker 

    DOCKER_CMD="docker run \
        -u 0 \
        -it \
        --rm \
        --env-file=${PWD}/.env \
        -e BACKUPS_WORLD_FOLDER=/opt/minecraft/backups \
        -v ${PWD}/live/volumes-${VERSION}/log:/opt/minecraft/log \
        -v ${BACKUP_FOLDER}:/opt/minecraft/backups \
        --name ${IMAGE}_${VERSION}_prune_standalone \
        ${IMAGE}:${VERSION} \
        ./scripts/./prune_standalone.sh"

        # /bin/bash"
        # ./scripts/./prune_standalone.sh"
    
    echo "${DOCKER_CMD}"

    ${DOCKER_CMD}

fi 