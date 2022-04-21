FROM debian:stable-slim

RUN apt -y update \
  && apt -y install \ 
    build-essential \
    ca-certificates-java \
    git \
    openjdk-17-jdk \
    wget \
    gettext-base \
    procps \
    telnet \
    vim \
  && apt clean \
  && rm -rf /var/cache \
  && update-ca-certificates -f

ENV HOME /opt/minecraft
ENV JAVA_TOOL_OPTIONS=-XX:+UseContainerSupport

WORKDIR ${HOME}

RUN mkdir -p ${HOME}/backups \
  && mkdir -p ${HOME}/tools \
  && mkdir -p ${HOME}/log
  
COPY scripts ./scripts

RUN echo ". ${HOME}/scripts/backup.sh" >> ${HOME}/.bashrc

VOLUME ${HOME}/backups
