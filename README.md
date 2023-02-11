# Quick Start

Don't care about the details?

```
minikube-minecraft $ minikube start 
```

When `minikube status` shows `running`:

```
minikube-minecraft $ ./install.sh 
minikube-minecraft $ cd java 
minikube-minecraft/java $ ./build 
minikube-minecraft/java $ ./deploy up
```

### Connecting multiplayer 

The following are all valid methods for connecting to the server:

* minikube tunnel + kubectl get service, look for desired NodePort service: Cluster IP + 25565
* docker inspect POD container: POD IP + 25565
* minikube service --all: associated URL for 25565 target port 
* proxy: localhost + incremented port 

If you need to expose your minecraft server anywhere off the host, even on the same 
network, the proxy server needs to be running:

```
minikube-minecraft/java $ cd ../proxy 
minikube-minecraft/proxy $ ./run.sh start 
```

_and_ the following requirements must be met:

* your host and/or router firewall are configured to allow TCP <incremented port> to your host machine 
* any port forwarding on the router is set up for port <incremented port> -> host machine 

Now, you can add a multiplayer server at `<your hostname>:<incremented port>`

### Development 

* fix backup compacting / pruning 
* Makefile 
* sub-versions on server versions using standard-version, at least for image tagging (minecraft-server-java:1.19.3-1.0.4) 

## 3/29/22 

### The Networking 

Ultimately, it would be great to feed and store world data during gameplay from 
physical storage, where it would be subject to all the trappings of a resilient,
backed-up system and we would be free to choose things like whether gameplay disk 
I/O was on SSD or RAID 1. Several layers of abstraction later, that utopia of 
nerdy minecrafting may be a far reach. But we can get close.

The networking for Minecraft hosted on Minikube looks something like this:

```
$ sudo route -ne 
...
172.17.0.4      192.168.49.2    255.255.255.255 UGH       0 0          0 br-8d38ed736202
(172.17.0.4/32 -> 192.168.49.2 on minikube bridge docker network interface)
...
```

```
host (192.168.1.2)
|-- host network 
    - minecraft-proxy container (host IP)
      [ 25565 minecraft-server <- NodePort service <- 25565 minikube container <- 25565 172.17.0.4 <- 25565 host ] (per 172.17.0.4 route)
|-- bridge network 192.168.49.1
    - minikube (192.168.49.2)
      |-- bridge network 172.17.0.1
          - minecraft-server container (172.17.0.4)
```

_The minecraft-proxy container and the route table entry are not necessary if you only want to play on the machine that's hosting minikube. In that case, minikube is already exposing aforwarded port to the NodePort service cluster IP, and that forwarded port is available to the host because minikube is on a bridge network. But it's not available anywhere else, because only the host has a route table entry for its docker bridge networks._

For Minecraft to be exposed on the network, the minikube host machine must 
serve a port that is redirected to minikube itself. That is the job of the 
minecraft proxy, and there are actually three ways it could do this.

1. Targeting the minecraft NodePort service cluster IP while running `minikube tunnel`.
2. Targeting the minikube container IP and the forwarded port from the NodePort service.
3. Targeting a special IP, specifically routed to the minikube container.

`1` is messy because we always need to tunnel the overlay network. `2` is messy because 
that forwarded port is random. `3`, then? It also needs a tunnel, but it's one we 
have more control over and doesn't conflict with the minikube conventions, i.e. 
we tunnel a single IP off to the side and the official minikube overlay tunnel 
can come and go as it pleases without interference.

See [the proxy readme](proxy/README.md) for further instructions.

### Storage and Backups

Now that our containers are all up and chatty, how do we assure that everything 
can burn to the ground and come right back? 

Well, it's something. Let's get to it. 

This project targets minikube, and so that's the kind of detail we're going to cover. 
This platform choice has triggered several interesting hurdles, juggling backups
not the least of them. (see Networking). 

`PersistentVolumes` will carve out of the minikube container's ephemeral 
storage and we, in fact, target a `minecraft` folder directly in `/home/docker` for 
all PVs:

```
/home/docker/minecraft/
  java\
    volumes-<version>\
      backups\  <-- java <version> backups PV
      world\    <-- java <version> world PV
  bedrock\
    volumes-<version>\
      backups\  <-- bedrock <version backups PV
      world\    <-- bedrock <version> world PV
```

Mounting these volumes into our server container:

```
/opt/minecraft/
  backups/
  server/
    worlds/<world name>/  <-- bedrock
    <world name>/         <-- java 
```

we run two cronjobs:

* within the server container to create a backup in the backups folder 
* on the host to `docker cp` all backups from the version-appropriate minikube container folder listed above onto host storage

Backups are filed by version and further by "level name" or "world name" (depending on what part of the system you're looking at).

This is all well and good for a first run, but let's tackle some problems out of the gate:

* on minikube restarts, PVs will continue to exist, but since the minikube container ephemeral storage resets, PV storage contents get wiped
* because PV storage contents wipe between cluster restarts but the configured world name remains the same, we now have a new base state for that world (in name only) and that name now refers to multiple worlds

Therefore, some special handling needs to be done when minikube restarts and also when we want to switch worlds. To even be able to respond properly,
backups need to be stored methodically and we need some sane defaults for handling unexpected circumstances.


* `deploy` can be provided with a world name, or not in which case the previously set world name will be found
* world data can exist (or not) for the provided or found world name
* backups can exist (or not) for the provided or found world name 



What happens next is more important. When the server starts, if the world data folder is empty, a new world is generated. Because both java and bedrock editions use world-named subfolders and not generic "world" folders, for a long-running server the world data folder in question may well be populated. But if minikube has been restarted and the world PV is based on ephemeral storage, the server may generate a new world when it shouldn't. Before the server is deployed and started, therefore, we need to know if the world in question has backups and then to load in the latest backup if so. 

1. check world data folder 


If minikube restarts for any reason, when it comes back up we will have a new, empty world named for whatever world was loaded in last. Backups will automatically start running, and the very first backup will be incorrect - it will be named for some world that might have hours of play on it but the backup contents will be 5-10 minutes into a brand new world. We want to at least give this world and its backups a distinct and correct name. 

For when the server is deployed intentionally we can inject a world from a backup ahead of time. If the server is already running, we can take a final backup and shut it down first. The first `deploy` should include the world name, but without is tantamount to the server coming up after a minikube restart. We can assume that if world data is present on the volume it corresponds to the world name in the environment, and so subsequent `deploy` commands, up or down, default to the pre-existing world.


_Detect a server starting without a world loaded and intercept the world name in the environment (coming from the Configmap). Call it "New World <timestamp>". Use this generated name for the backup file, but don't bother changing the Configmap value because another minikube restart will wipe it out anyway._

States:
* server deployed 
* server torn down

Scenarios:
* server starts with no world data
* a world is loaded by name when the server is already running 
* a world is loaded by name when the server is stopped
* the server is 

`deploy` and `load` also may be affected in how they interact with `.env`. 

`deploy up` will create PV/PVC if they don't exist and never drop them, even with `deploy down`.
`load` will wrap placement of world data (from a backup) and changing of the world name in `.env` with a `deploy down && deploy up`.



, which will persist between minikube restarts. So the minecraft server 
come and go, trash it all you want. With your volume claims in place, gameplay is 
real-time living on a normal docker container on your host machine, not an 
abstraction of an abstraction of a disk somewhere in kubernetes. We can get to it 
easily with `docker cp`, and the server itself can be loaded with a backup script 
to archive your worlds away, worlds away if you like.

And so the old adage goes, "you're not backed up until you restore". (I think it says that?)

Since the server itself can run in so many ways, we should cover backup creation, 
collection, and restoration as succinctly as possible.

For simplicity, let's assume we're always at least running in a container. And 
environment will be fed to the container on start for server.properties, so we don't 
need to rebuild the image to switch between creative and survival and things like 
that. Let's also make sure that environment file is single-sourced and the server 
start always looks in one place for the file regardless of the container context, 
so changes only happen in one place. 

For a plain old container, we can volume in the environment file directly to 
the expected location. Stopping and starting the container will reset server 
parameters.

For a deployment container, the file can be volumed in from a file-format ConfigMap.
In this case, we will need to recreate the ConfigMap and restart the pod to affect 
server parameter changes.

So, back to backups. The container is the same everywhere, and backups will go to 
a single backups folder regardless of context. But since the pod gets its storage 
through persistent volumes from the minikube container and a plain old container 
will get a volume directly from the host, there's a necessary disconnect between 
deployment contexts in how we collect backups. We also have world saves from 
remote servers in `~/.minecraft/saves` to consider, and one of the bigger 
differences with remote server saves is that those are named, while the local 
server backups, most notably on java edition, are not. Bedrock worlds are named,
but an archive grab of the world folder is not inherently aware of that name.
So, included in the local server container will need to be a `world name` value 
that the backup script can use to file its artifacts in appropriate subfolders.
The value for `world name` in Java edition will need to be set based on any 
backup that might have been restored. And if no world is being restored, the 
value will be a new name and a new backups subfolder. In Bedrock edition, the 
name must be set explicitly in server.properties, and since the backup script 
needs it in both editions, it should source from the common environment file 
and then server.properties will inherit it. 

*Pod*

```
pod ->  minikube container ->   host 
```

scripts/backup.sh to /opt/minecraft/backups 
persistent volume maps /home/docker/minecraft/volumes/backups -> /opt/minecraft/backups 
cron from minikube:/home/docker/minecraft/volumes/backups to BACKUPS 

*Container*

```
plain old container ->  host 
```

scripts/backup.sh to /opt/minecraft/backups 
container volume maps live/backups -> /opt/minecraft/backups 
cron from live/backups to BACKUPS 

*Remote server*

```
home folder                 ->  host 
```

cron from ~/.minecraft/saves to BACKUPS 


It's basic enough to "feed" the minecraft server with a `world` folder. There's
your restore. It gets a little complex when you want to make it resilient to 
all the sorts of ways the minecraft server and minikube cluster can be interrupted 
and destroyed, and further, provide a easy-to-use interface for humans to manage 
this feeding so that any one of multiple worlds can be loaded and each will be backed 
up on their own timelines. 

A good minimal interface for something like this..

- minimize restarts and changes 
- what does this look like on the command line?
- what are the actual operations to swap worlds?
- what does the storage architecture actually look like?

#### The Storage Architecture (what it looks like)

```
       k8s volume claims     <---       minecraft server container   |
     k8s persistent volumes          docker daemon ephemeral storage | -- this is k8s deployment-land, but let's call it what it is
              minikube container ephemeral storage 
                       docker root dir
                    minikube host machine 
```

We're glossing over the nuts and bolts of folders mounted in containers and how
this is all represented by K8s volumes, claims and deployments. The important 
parts here are 

- what happens to any of this when things are shut down or destroyed
- how to structure storage so that runtime minecraft I/O occurs at the lowest/safest level possible 
- how to manage files-on-disk for backup and restore 

*Minikube Container*

A good generic k8s volume organization will let us be free to choose structure 
per workload and maintain a convention.

`/home/docker` <-- we get this out of the box 
  `<topic>/volumes/<opaque>` <-- we create this to support our workload 
    - topic: "minecraft"
    - opaque: minecraft-internal storage conventions (server/world, backup, tools, etc.)
      - for java edition, this is /world and /backups 
      - for bedrock edition, this is _/worlds_ and /backups 
      - also note, for bedrock, the 's' worlds implies accurately that multiple worlds are contained by subfolder, selected at server startup by `level-name` in `server.properties`
  
  With this, let's have 
  This leaves us free to make decisions like "should the whole `minecraft` folder 
  as the server sees it be in a single volume, or should volumes be purpose-driven,
  like backup-volume, world-volume, etc." _for minecraft_, and then do something 
  completely different for another kind of workload.
  
  Let's try `/home/docker/minecraft/volumes/backup`


There's not a lot of options for customizing the minikube container built into 
the startup process, but it can be freely modified after it's up and running.


minikube start 
docker cp backups/20220329T141823/server/world minikube:/home/docker/minecraft/
kubectl apply -f deploy/minecraft.yaml
cd proxy 
./run.sh 


## minikube

```
minikube start
eval $(minikube -p minikube docker-env)
docker build -t minecraft-server .
cd client

docker build -t minecraft-client .
cd ..
kubectl apply -f minecraft.yaml
kubectl run --rm mc --image=minecraft-client:latest --image-pull-policy=Never -i --tty
./mcrcon -H ${MINECRAFT_SERVICE_SERVICE_HOST} -P ${MINECRAFT_SERVICE_SERVICE_PORT_MCRCON} -p billybub

$ minikube service minecraft-service
|-----------|-------------------|---------------|---------------------------|
| NAMESPACE |       NAME        |  TARGET PORT  |            URL            |
|-----------|-------------------|---------------|---------------------------|
| default   | minecraft-service | default/25565 | http://192.168.49.2:30509 |
|           |                   | mcrcon/25575  | http://192.168.49.2:31889 |
|-----------|-------------------|---------------|---------------------------|

```

Add server @ 192.168.49.2:30509

## docker 

```
docker run --rm -it minecraft-server:latest 
docker run --rm -it minecraft-client:latest /bin/bash
```

# References

https://linuxize.com/post/how-to-install-minecraft-server-on-debian-9/
https://www.minecraft.net/en-us/download/server

# Appendix: Gotchas

* Building an image in the minikube docker environment or maybe in any environment 
is sometimes blocked, possibly by minecraft-proxy running. When the container 
is stopped and the script removes the route table entries, the build is able to 
resolve the debian repositories again. The java build also gets hung up on 
cloning mcrcon sometimes. 

# Appendix: March 2022 work 

### docker networks - host context

NETWORK ID     NAME            DRIVER    SCOPE
26549037e3b5   bridge          bridge    local -> 172.17.0.0/16 (grocerier)
5de00299b771   frankenbridge   bridge    local -> 172.18.0.0/16 (frankdbs, blog_app, proxy)
5e5b59bcf4cb   host            host      local
8d38ed736202   minikube        bridge    local -> 192.168.49.0/24 (minikube)
01d06a142c81   none            null      local

### docker networks - minikube context

NETWORK ID     NAME      DRIVER    SCOPE
98b47451df02   bridge    bridge    local -> 172.17.0.0/16 (POD_minecraft, kube-system, dashboard, ingress)
c4011c144ec4   host      host      local -> (more kube-system containers)
c06eae8a10ba   none      null      local

### interfaces 

### frankenbridge docker network 
br-5de00299b771 172.18.0.1/16 
all frank pods not in minikube run here 

### the named "bridge" bridge network in both docker contexts
docker0 172.17.0.1/16 
some minikube-context containers run in 172.17 but nothing from the host-context 

### minikube container (minikube is 192.168.49.2)
br-8d38ed736202 192.168.49.1/24

A clearer demarcation between "interfaces" and "networks" needs to be drawn.

Interfaces are strictly a concept of their native docker context, i.e. the minikube 
container has bridge (br-*) interfaces representing docker networks for the minikube 
container docker daemon and the host has bridge interfaces representing docker 
networks for the host docker daemon. 

Since minikube has its own bridge network 
on the host, this means the host has a dedicated minikube bridge interface. 

In any docker context, a "bridge"-named bridge network exists for 172.17 and its 
representative interface is called "docker0". 

The minikube bridge network is 192.168.49.1/24.

That bridge network and the minikube container itself at 192.168.49.2 is, of course,
reachable from the host, just like any other bridge network. But this bridge 
network is a little different. One, it has its own docker daemon and environment,
which is a totally separate level of containers and further bridge (and host)
networks with their own subnets and IP addresses. These networks are not reachable 
from the host, however similar they might look to those directly on the host.
For example, both environments have a "bridge" bridge network at 172.17.0.0/24
and both have a "host" host network that can see all the interfaces of their 
respective hosts. But the "host" docker network in the minikube container can 
really only see the small set of interfaces available on the minikube container,
and nothing of your main host machine. The second reason the minikube bridge 
network is different is that within it, running on the minikube container itself,
lies the k8s overlay network. This is a large /12 subnet owned and operated by 
k8s itself. When a k8s service is created for a container/pod, the cluster IP assigned to 
it comes from this /12 network. The workload container itself will have an IP 
address of the 172.17.0.0/24 bridge network in the minikube docker environment,
but its service cluster IP will be the overlay. 

So just in the one minikube bridge network we have a 192.168.0.0/24 network for 
the minikube container itself, a number of 172.x minikube-level docker networks, 
a host network, and the overlay network. Only one of these is reachable from the host -
the minikube bridge network, as every bridge network is reachable from its host.
The other two need special routing. `minikube tunnel` will pass the overlay 
network up to the host, allowing direct addressing for any cluster IP. This 
actually works by directing that traffic to the already reachable minikube 
container and letting k8s figure it out. This is essentially a mapping of 
172.17 minikube-level bridge network IP addresses to an index of overlay network 
IP addresses. Really, I would think, in theory, `kubectl` could expose the 172.17
addresses directly, and `minikube tunnel` might as well route those addresses to
k8s instead, but then we'd be interfering with the host-level bridge networks 
already in that 172.17 IP space. So the overlay network is also a disambiguating 
network. The other networks - the 

Bridge networks in different docker environments cannot normally talk to each other,
and their IP address ranges really mean nothing. However, any bridge network container 
can be reached from its native docker context. Messing with `minikube docker-env` 
can be confusing then, because you can see containers and networks that are 
unreachable. It's better to just `minikube ssh` if a view of the minikube docker 
environment is needed. 

Host traffic will only travel to docker networks in the host docker environment and 
the same goes for minikube traffic. This behavior can be modified, however,
with the route table. A k8s service in minikube will have a cluster IP for the 
miniube overlay network (something in 10.96.0.0/12 -ish). That service target 
container can be reached in two ways. One is with the minikube "container port",
which can be seen with `minikube service --url <service name>`. This will be the 
port you want on the k8s container forwarded through k8s networking to a random 
port on the k8s node. It's important to note here that when minikube tells you "NodePort",
it's referring to the minikube container as the node. Yes, your service is "exposed"
through a port on the node, but that node is tucked into a bridge network container 
on your computer. The other way is with `minikube tunnel`, which creates the 
following route on the host:

```
Destination     Gateway         Genmask         Flags   MSS Window  irtt Iface
10.96.0.0       192.168.49.2    255.240.0.0     UG        0 0          0 br-8d38ed736202
```

If the minikube container port gets you to the service cluster IP for your workload 
via the overlay network, this brings the overlay network right up to your host. 
It's like l;e
That interface is the `minikube` docker bridge network interface on minikube's host.
The rule redirects 10.96/12 traffic to the minikube container, where the k8s overlay 
network and routing will take over and allow it to reach the service cluster IP 
and ultimately the service target container. Note that the container itself is somewhere 
in 172.17.0.1/24.. we're not using the bridge network IP address at all., but we don't strictly have a route to that subnet from the host. 
We can't hit any 172.17 address from the host or from any container on the host-native 
docker environment for that matter, even a 172.17 host container. Because the host docker 
networks are completely separate from the minikube docker networks.

So how do we reach minikube docker networks from the host without tunneling?
In Openshift, this is where routes come in. Openshift will use the `host` header 
to match up traffic with a pod, leaving IP addresses out of the equation entirely.
But without hostname routing, we need to rely on layer 3 constructs.

The route table can help us! 



Notice that with "tunneling", the k8s overlay network is fully exposed to the host 
not by directing 10.96/12 host traffic to 10.96/12 traffic on a docker network 
but by pointing it right at the minikube container and letting k8s sort it out.
We 


### the actual things we're trying to hit 

#### container 
k8s_minecraft-server_minecraft-75dd9f567c-hg9fz_default_d074aa97-5ba4-4fbe-aaaf-d7cf9ef2007c_0
- no network settings 
- container ports 25565, 25575
- env MINECRAFT_SERVICE* points to 10.101.245.72:25565/25575 
- env KUBERNETES* points to 10.96.0.1:443 
- exposed ports 25565/tcp 25575/tcp
- no networks 

#### container 
k8s_POD_minecraft-75dd9f567c-hg9fz_default_d074aa97-5ba4-4fbe-aaaf-d7cf9ef2007c_0
- gateway 172.17.0.1 / ip 172.17.0.6 
- no mounts, no env 
- "bridge" network 


1. stand up minikube. minikube creates a docker bridge network, an interface
representing that network, and a route table for 192.168.49.0/24 to that interface.
we also have a ClusterIP service showing a 10.96.0.1 address that doesn't appear 
anywhere else yet.

```

ip addr 
br-8d38ed736202 192.168.49.1/24 brd 192.168.49.255 scope global br-8d38ed736202

sudo route -ne 
192.168.49.0    0.0.0.0         255.255.255.0   U         0 0          0 br-8d38ed736202

kubectl get svc 

NAME            TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)           AGE
kubernetes      ClusterIP      10.96.0.1       <none>        443/TCP           94d
```

2. create a minecraft pod and 25565/TCP LoadBalancer service. we can see the new 
service with its own cluster IP, but not available external to the cluster:

```
kubectl get svc 

NAME            TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)           AGE
kubernetes      ClusterIP      10.96.0.1       <none>        443/TCP           94d
minecraft-tcp   LoadBalancer   10.110.46.182   <pending>     25565:31163/TCP   3s
```

3. ah, but wait! even though the LoadBalancer service doesn't have an external IP,
it does have a "kubernetes URL", which appears to be the LoadBalancer service 
represented through the kube-ingress-dns-minikube pod as a "forwarded port??",
and a local (host) client can connect to minecraft there:

```
minikube service --url minecraft-tcp
http://192.168.49.2:31163
```
  
8. now if we tunnel, a route table entry is created for 10.96.0.0/12 to that 
192.168.49.2 address. this covers the 10.110.46.182 cluster IP of our LoadBalancer 
service, making that IP address now "external" to the cluster, and a host-local 
client can connect to minecraft on this external IP at port 25565 

```
  minikube tunnel
  Status:	
   machine: minikube
   pid: 2552998
   route: 10.96.0.0/12 -> 192.168.49.2
   minikube: Running
   services: [minecraft-tcp]
     errors: 
     minikube: no errors
     router: no errors
     loadbalancer emulator: no errors

sudo route -ne 
10.96.0.0       192.168.49.2    255.240.0.0     UG        0 0          0 br-8d38ed736202

kubectl get svc 

NAME            TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)           AGE
kubernetes      ClusterIP      10.96.0.1       <none>          443/TCP           94d
minecraft-tcp   LoadBalancer   10.110.46.182   10.110.46.182   25565:31163/TCP   3m

```

9. creating a NodePort service gives a new cluster IP

```
kubectl get svc
NAME                TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                           AGE
kubernetes          ClusterIP      10.96.0.1        <none>        443/TCP                           94d
minecraft-service   NodePort       10.110.160.137   <none>        25565:30075/TCP,25575:31914/TCP   6s
minecraft-tcp       LoadBalancer   10.110.46.182    <pending>     25565:31163/TCP                   7h23m

10. creating an ingress for the nodeport seems to not do anything extra for the nodeport service 
but it blocks the minecraft client from connecting to the minikube IP: http://192.168.49.2:31163
```







10.96.0.1    <-- "kubernetes" ClusterIP service cluster IP address (443/tcp)
  - actually trying to hit this gets a 403, system:anonymous cannot get path /
192.168.49.0
10.110.46.182







# -- the client can access the server through the TCP load balancer to 25565 
minikube service --url minecraft-tcp 
http://192.168.49.2:30682

# -- the tunnel
minikube tunnel 
Status:	
	machine: minikube
	pid: 2271079
	route: 10.96.0.0/12 -> 192.168.49.2
	minikube: Running
	services: [minecraft]
    errors: 
		minikube: no errors
		router: no errors
		loadbalancer emulator: no errors
# -- creates the route table entry
10.96.0.0       192.168.49.2    255.240.0.0     UG        0 0          0 br-8d38ed736202
# -- and gives the loadbalancer service an external IP
# -- from this
minecraft           LoadBalancer   10.101.75.129   <pending>       25565:30126/TCP                   154m
# -- to this 
minecraft           LoadBalancer   10.101.75.129   10.101.75.129   25565:30126/TCP                   154m
# -- and allows access on frankendeb to 10.101.75.129:25565 


# -- this route allows minecraft client to reach the server at 172.17.0.6:25565 
route add -net 172.17.0.6 netmask 255.255.255.255 gw 192.168.49.2 dev br-8d38ed736202
route del -net 172.17.0.6 netmask 255.255.255.255 gw 192.168.49.2 dev br-8d38ed736202

# Appendix: Mods

Forge must be installed on the client per launcher configuration. Really, for any one version,
there should only be one install with and without Forge, and unless there are old world
versions, it doesn't make sense to have any non-latest-version non-Forge versions, and it
doesn't make sense to have Forge on any versions you don't have mods for. So the setup will 
be one latest non-Forge (clean) version, and one Forge install for each older version for which 
you have mods.

To install mods, typically a .jar file will be placed inside `.minecraft/mods`. Often, mods
will have dependencies, also as .jar files in the same folder. Mods are only loaded when 
a Forge version is being run, otherwise these files are ignored. 

While Forge is installed per launcher install version, and mods are built per-version,
everything goes into the one mods folder and when a launcher configuration is started,
everything is attempted to be loaded, and what will fail will fail. So the contents of the 
mods folder must be adjusted per client version that's being used at the time. 

So a typical workflow is thus:

* create a new installation (launcher configuration) with the version desired
* download Forge for that version
* run the Forge .jar (java -jar ...jar) and install for client 
* download mods desired for the version
* put mods .jar files into `.minecraft/mods`
* start minecraft launcher, select the Forge-enabled installation
* Play 

For 1.16.5 with Morph and Rats, `~/.minecraft/mods` looks like:

```
./rats-7.2.0-1.16.5.jar
./Morph-1.16.5-10.1.1.jar
./citadel-1.7.0-1.16.5.jar
./iChunUtil-1.16.5-10.5.2.jar
```

# Appendix: mcrcon help

```
/advancement (grant|revoke)
/attribute <target> <attribute> (base|get|modifier)
/ban <targets> [<reason>]
/ban-ip <target> [<reason>]
/banlist [ips|players]
/bossbar (add|get|list|remove|set)
/clear [<targets>]
/clone <begin> <end> <destination> [filtered|masked|replace]
/data (get|merge|modify|remove)
/datapack (disable|enable|list)
/debug (report|start|stop)
/defaultgamemode (adventure|creative|spectator|survival)
/deop <targets>
/difficulty [easy|hard|normal|peaceful]
/effect (clear|give)
/enchant <targets> <enchantment> [<level>]
/execute (align|anchored|as|at|facing|if|in|positioned|rotated|run|store|unless)
/experience (add|query|set)
/fill <from> <to> <block> [destroy|hollow|keep|outline|replace]
/forceload (add|query|remove)
/function <name>
/gamemode (adventure|creative|spectator|survival)
/gamerule (announceAdvancements|commandBlockOutput|disableElytraMovementCheck|disableRaids|doDaylightCycle|doEntityDrops|doFireTick|doImmediateRespawn|doInsomnia|doLimitedCrafting|doMobLoot|doMobSpawning|doPatrolSpawning|doTileDrops|doTraderSpawning|doWeatherCycle|drowningDamage|fallDamage|fireDamage|forgiveDeadPlayers|keepInventory|logAdminCommands|maxCommandChainLength|maxEntityCramming|mobGriefing|naturalRegeneration|randomTickSpeed|reducedDebugInfo|sendCommandFeedback|showDeathMessages|spawnRadius|spectatorsGenerateChunks|universalAnger)
/give <targets> <item> [<count>]
/help [<command>]
/kick <targets> [<reason>]
/kill [<targets>]
/list [uuids]
/locate (bastion_remnant|buried_treasure|desert_pyramid|endcity|fortress|igloo|jungle_pyramid|mansion|mineshaft|monument|nether_fossil|ocean_ruin|pillager_outpost|ruined_portal|shipwreck|stronghold|swamp_hut|village)
/locatebiome <biome>
/loot (give|insert|replace|spawn)
/me <action>
/msg <targets> <message>
/op <targets>
/pardon <targets>
/pardon-ip <target>
/particle <name> [<pos>]
/playsound <sound> (ambient|block|hostile|master|music|neutral|player|record|voice|weather)
/recipe (give|take)
/reload
/replaceitem (block|entity)
/save-all [flush]
/save-off
/save-on
/say <message>
/schedule (clear|function)
/scoreboard (objectives|players)
/seed
/setblock <pos> <block> [destroy|keep|replace]
/setidletimeout <minutes>
/setworldspawn [<pos>]
/spawnpoint [<targets>]
/spectate [<target>]
/spreadplayers <center> <spreadDistance> <maxRange> (under|<respectTeams>)
/stop
/stopsound <targets> [*|ambient|block|hostile|master|music|neutral|player|record|voice|weather]
/summon <entity> [<pos>]
/tag <targets> (add|list|remove)