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

COPY nginx-tcp.conf.tmpl .
COPY nginx-udp.conf.tmpl .
COPY start.sh .
RUN chmod +x start.sh

ENTRYPOINT ["./start.sh"]
