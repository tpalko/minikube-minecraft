FROM minecraft-server-base:latest

# -- install RCON client 
WORKDIR ${HOME}/tools 
RUN git clone https://github.com/Tiiffi/mcrcon.git \
  && cd mcrcon \
  && gcc -std=gnu11 -pedantic -Wall -Wextra -O2 -s -o mcrcon mcrcon.c 

# -- download server
WORKDIR ${HOME}/server

ARG HASH
ENV HASH=${HASH}

RUN wget https://launcher.mojang.com/v1/objects/${HASH}/server.jar

# -- 1.19.3
#RUN wget https://launcher.mojang.com/v1/objects/c9df48efed58511cdd0213c56b9013a7b5c9ac1f/server.jar
# -- 1.18.2
#RUN wget https://launcher.mojang.com/v1/objects/c8f83c5655308435b3dcf03c06d9fe8740a77469/server.jar
# -- 1.18.1
#RUN wget https://launcher.mojang.com/v1/objects/125e5adf40c659fd3bce3e66e67a16bb49ecc1b9/server.jar
# -- 1.16.5
#RUN wget https://launcher.mojang.com/v1/objects/1b557e7b033b583cd9f66746b7a9ab1ec1673ced/server.jar
# -- 1.16.3
#RUN wget https://launcher.mojang.com/v1/objects/f02f4473dbf152c23d7d484952121db0b36698cb/server.jar

# RUN mkdir patch \
#   && cd patch \
#   && wget https://launcher.mojang.com/v1/objects/02937d122c86ce73319ef9975b58896fc1b491d1/log4j2_112-116.xml \
#   && chmod 755 log4j2_112-116.xml

RUN java -Xmx1024M -Xms1024M -jar server.jar nogui || echo "that's ok" \
  && sed -i "s/eula=false/eula=true/" eula.txt

WORKDIR ${HOME}

RUN useradd -r -m -U -d ${HOME} -s /bin/bash minecraft

COPY start.sh .


RUN chown -R minecraft:minecraft . \
  && find . -name *.sh -execdir chmod +x '{}' \;

COPY patch ./server/patch

EXPOSE 25565
EXPOSE 25575

USER minecraft 

# VOLUME /opt/minecraft/server/world 

CMD ["./start.sh"]
