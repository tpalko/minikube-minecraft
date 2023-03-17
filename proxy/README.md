# minecraft-proxy

`run.sh` is your deploy script. It expects 

1. `minikube` to be running, as the associated docker containers and route table entries are how this proxy does its job

2. The minecraft server and NodePort service (see [the parent readme](../README.md)).

3. a host machine route table entry the proxy can point to, away from everything 
else, to get to the minikube container:

```
route add -net 172.17.0.4 gw $(minikube ip) netmask 255.255.255.255 dev br-$(docker network ls --filter="name=minikube" -q)
```

In theory, that `172.17.0.4` can be anything. `minikube` is going to be routing 
the traffic by port, not IP address.

4. Some Nginx config to catch traffic on a host machine port and send it down 
that route table entry we just created.

```
printf "UPSTREAM_HOST=172.17.0.4\nUPSTREAM_PORT=25565\n" > .env 
```

5. To be able to listen for host machine port traffic.

6. To be able to reach the network for the route table entry.

`run.sh` will run this Nginx container on the host network 
and listen on port `25565`, sending this traffic by way of the route table entry (#4, #5)
to the minikube container (#6) on the same port:

```
./run.sh 
```
