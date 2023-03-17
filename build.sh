#!/bin/bash 

echo "Building base image: $@"

docker build $@ -t minecraft-server-base:latest .
