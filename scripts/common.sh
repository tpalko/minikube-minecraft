function version_parameter() {
  PARAMETER=$1
  cat .jenv | jq -r ".worlds | .[] | select(.version == \"${VERSION}\") | .${PARAMETER}"
}

function target_platform_cmd() {
  local CMD="$1"
#   echo "Executing on \"${TARGET_PLATFORM}\": ${CMD}"
  case ${TARGET_PLATFORM} in 
    minikube)   minikube ssh "${CMD}"
                ;;
    docker)     ${CMD}
                ;;
  esac                 
}

VERSION_ARRAY=($(cat .jenv | jq -r ".worlds | .[] | .version"))
echo "Found ${#VERSION_ARRAY[@]} versions: ${VERSION_ARRAY[@]}"