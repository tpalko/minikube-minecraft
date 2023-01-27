FROM debian:latest

RUN apt-get -y update \
  && apt-get -y upgrade \
  && apt-get -y install \
    netcat \
    gettext-base \
    iputils-ping \
    nginx-full \
    telnet \
    vim \
    wget \
  && rm -f /etc/nginx/sites-enabled/default \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN useradd -r -U nginx 

COPY nginx-bedrock-tcp.conf.tmpl .
COPY nginx-bedrock-udp.conf.tmpl .
COPY nginx-java-tcp.conf.tmpl .

COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
