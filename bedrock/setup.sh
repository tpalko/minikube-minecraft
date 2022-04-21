#!?bin/bash 

set -e 

RANDOM_AGENT=$(echo $(( 1 + $RANDOM % 5000 ))) \
  && mkdir -p {downloads,server}  \
  && curl -o downloads/version.html -H "Accept-Encoding: identity" -H "Accept-Language: en" -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.33 (KHTML, like Gecko) Chrome/90.0.${RANDOM_AGENT}.212 Safari/537.33" https://minecraft.net/en-us/download/server/bedrock/ \
  && URL=$(grep -o 'https://minecraft.azureedge.net/bin-linux/[^"]*' downloads/version.html) \
  && echo "URL: ${URL}" \
  && FILE=$(echo "$URL" | sed 's#.*/##') \
  && echo "File: ${FILE}" \
  && curl -H "Accept-Encoding: identity" -H "Accept-Language: en" -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.33 (KHTML, like Gecko) Chrome/90.0.${RANDOM_AGENT}.212 Safari/537.33" -o "downloads/$FILE" "$URL" \
  && unzip downloads/$FILE -d server
