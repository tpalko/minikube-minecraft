FROM minecraft-server-base:latest

RUN mkdir -p /var/cache/apt/archives/partial \
  && apt-get -y update \
  && apt-get -y install \
    curl \
    unzip \
  && apt clean \
  && rm -rf /var/cache 

# COPY live/downloads ./downloads

COPY setup.sh .
RUN /bin/bash setup.sh 

COPY start.sh .

RUN mkdir -p server/worlds \
  && find . -name "*.sh" -execdir chmod +x '{}' \;

EXPOSE 19132/tcp
EXPOSE 19132/udp

# VOLUME /opt/minecraft/server/worlds

CMD ["./start.sh"]
