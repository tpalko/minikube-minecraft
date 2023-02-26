#!/bin/bash 

set -e 

mkdir -vp {downloads,server}

if [[ ! -f downloads/version.html ]]; then 

  echo "version.html doesn't exist.. fetching it"

  VERSION_URL="https://minecraft.net/en-us/download/server/bedrock/"
  RANDOM_AGENT=$(echo $(( 1 + $RANDOM % 5000 )))
  USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.33 (KHTML, like Gecko) Chrome/90.0.${RANDOM_AGENT}.212 Safari/537.33"
  
  curl -o downloads/version.html \
    -H "Accept-Encoding: identity" \
    -H "Accept-Language: en" \
    -L \
    -A "${USER_AGENT}" \
    --url "${VERSION_URL}"  
fi

# something like..
# https://minecraft.azureedge.net/bin-linux/bedrock-server-1.19.62.01.zip
URL=$(grep -o 'https://minecraft.azureedge.net/bin-linux/[^"]*' downloads/version.html) \
    && echo "URL: ${URL}" \
    && FILE=$(echo "$URL" | sed 's#.*/##')

if [[ ! -f downloads/${FILE} ]]; then 
  echo "downloads/${FILE} doesn't exist.. fetching it from ${URL}" \
    && curl \
      -H "Accept-Encoding: identity" \
      -H "Accept-Language: en" \
      -L \
      -A "${USER_AGENT}" \
      -o "downloads/$FILE" \
      --url "$URL"
fi

unzip downloads/$FILE -d server
