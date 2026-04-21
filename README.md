# 2026 Docker Workshop

## Introduction to Docker

> The goal of this bootcamp exercise is to provide an overview of one of the newer components of CI/CD: containers.

### What is Docker?

_![That's a big question](https://31.media.tumblr.com/a4a72524f0bc49663881898367b5246a/tumblr_ns8pm9eEwN1tq4of6o1_540.gif)_

In their own words:

> Developing apps today requires so much more than writing code. Multiple languages, frameworks, architectures, and discontinuous interfaces between tools for each lifecycle stage creates enormous complexity. Docker simplifies and accelerates your workflow, while giving developers the freedom to innovate with their choice of tools, application stacks, and deployment environments for each project.

Essentially, 

- Docker is a tool that allows you to package code into a Docker image (a re-usable file used to execute code in a Docker container).
- Docker images are the blueprint for Docker containers, which are isolated execution environments.

### Why use Docker?

- Docker is a standard package that works across multiple architectures and environment type. i.e. Build a single Docker image that would run the same on Windows vs Mac. 
- Integrate with popular [open-source solutions](https://hub.docker.com/search?q=&type=image) for databases, caching, monitoring, gaming, and more.
- Since each container is isolated by default, the security from Docker can be unparallelled. For example, consider a web appliction that runs inside of a container. If the application was compriomised by bad actors, they'd only have access to the contents of the container, and not the entire host filesystem.
- [So much more...](https://www.docker.com/use-cases)

### Install Docker

#### Mac Users

Install Brew (if needed):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Have Brew install Docker

```bash
brew install --cask docker
```

#### Windows Users

Windows is a little trickier...

##### WSL Setup
Installing Docker requires the [Windows Subsystem for Linux](https://learn.microsoft.com/en-us/windows/wsl/install) and the Ubuntu shell. Open PowerShell and type: 

```shell
wsl --install -d ubuntu
```

Then run:
```shell
wsl --set-default ubuntu
```

Open the WSL and create a user account for linux. 

##### Docker Desktop

Download and install Docker from here: https://docs.docker.com/desktop/install/windows-install/

Once the Docker Desktop software is installed. Go into the Settings and click on `Resources` and then `WSL Integration`. Make sure that `Ubuntu` is Enabled.

##### Make sure it works!

Run Ubuntu in Windows and then type:
```shell
sudo su -
```

Then type:

```shell
docker
```

This should print the Docker help menu.

### What does a Docker Image look like?

Let's take a look at the [Docker docs](https://docs.docker.com/language/python/build-images/#create-a-dockerfile-for-python) for creating a `Dockerfile` for a python application.

```Docker
# What is our base image? Since we want to create a python application, we need a base image that has python. Luckily, we can continue making use of open-source images for this as well. There are many types of images that provide python, but for this example i'll choose 
FROM python:3.13-slim-trixie

# What directory (inside the container) should we be working from?
WORKDIR /app

# Copy over the project requirements
COPY requirements.txt requirements.txt

# Run a command to install the requirements
RUN pip3 install -r requirements.txt

# Copy over the rest of the app
COPY . .

# The command for the container. If this command exits, the container exits.
CMD [ "python3", "-m" , "flask", "run", "--host=0.0.0.0"]
```

## Deploying an Open Source image

Each image is different in terms of how you configure the specifics for the application running inside. What's common though, is _how_ you configure the containers. Most images are configured using environment variables and/or by mounting a local Docker volume with configuration files present. 

Let's look at Redis, as it's a very popular and useful key-value store and caching solution.

### What is Redis?

On their website, they define themselves as:
> The open source, in-memory data store used by millions of developers as a database, cache, streaming engine, and message broker.

They also have a nice chart showing features:

_![Redis Features](docs/redis_features.png)_

On my team, we make use of a [library]([https://python-rq.org]) called `RQ-Python` that builds a queuing system for Python jobs on top of Redis. We create thousands of jobs each night and have hundreds of worker containers that perform the jobs.

Ok, let's get started.

### Pull the Valkey image

All we need to do is type `docker pull REPOSITORY[:TAG]`. What does this syntax mean? Well docker images are stored in repositories, just like code is stored in git repositories. By default, all images are pulled from DockerHub. You are able to create and manage your own image repositories, but we won't go over that. The image repository is required, but the tag isn't and will be defaulted to `latest` if nothing is given for it.

```bash
docker pull valkey/valkey:8-alpine
```

Which should output something like: 
```
Using default tag: latest
latest: Pulling from library/redis
Digest: sha256:7e2c6181ad5c425443b56c7c73a9cd6df24a122345847d1ea9bb86a5afc76325
Status: Image is up to date for valkey/valkey:8-alpine
docker.io/library/valkey/valkey:8-alpine
```

What is happening here? You are pulling the Valkey image from Docker Hub.

> Why Valkey in 2026? Redis remains popular, but many teams now choose Valkey (an open Redis-compatible fork) for fully open governance and licensing flexibility. The command set used in this workshop is compatible.

For reproducible builds, pin by digest when you move to CI:

```bash
docker buildx imagetools inspect valkey/valkey:8-alpine
# then use: valkey/valkey@sha256:<digest>
```

If you click on one of the tags in that repo, you can see the Dockerfile that backs the image. Here's an example of what an opensource image looks like: https://github.com/redis/docker-library-redis/blob/0d682fed252b85f39d2033294eab217be02f95a1/7.4-rc/debian/Dockerfile

### Inspect the Valkey image

To view the image details, we just need to type `docker images [REPOSITORY[:TAG]]`. This time, the repository is not required, but we are going to use it to limit our results to the image we want. For example:

```bash
docker images valkey/valkey
```

Which should output something like: 
```
REPOSITORY   TAG       IMAGE ID       CREATED       SIZE
redis        latest    fad0ee7e917a   2 weeks ago   105MB
```

What does this tell us? Well we are using the default image tag `latest` which will (in most cases) be the most recent version of the image. The `IMAGE ID` is a unique identifier for the image, and the `SIZE` is the size of the image on disk.

In this example, we can see that this particular image was built two weeks ago and is 105MB in size.

### Create Redis container

> Run the open-source image redis image (last arg), call it 'redis' (--name redis) and run it in detached mode (-d)

```bash
docker run --name redis -d valkey/valkey:8-alpine
```

This should spit out the docker image id, which is a unique identifier for the container. That's literally how easy it can be to run a Docker image.

### View Redis in container list

> Check the status of the container

```bash
docker ps
```

This should output something like: 
```
CONTAINER ID   IMAGE          COMMAND                  CREATED          STATUS          PORTS      NAMES
16ad2cca6925   valkey/valkey:8-alpine   "docker-entrypoint.s…"   22 seconds ago   Up 21 seconds   6379/tcp   redis
```

There's our docker container running with Redis inside of it. The `STATUS` column tells us that the container is `Up` and has been running for 21 seconds. The `PORTS` column tells us that the container is listening on port `6379`.

### Check Redis Logs
```bash
docker logs redis
```

Which outputs: 
```
1:C 26 Jun 2024 20:22:22.312 * oO0OoO0OoO0Oo Redis is starting oO0OoO0OoO0Oo
1:C 26 Jun 2024 20:22:22.312 * Redis version=7.2.5, bits=64, commit=00000000, modified=0, pid=1, just started
1:C 26 Jun 2024 20:22:22.312 # Warning: no config file specified, using the default config. In order to specify a config file use redis-server /path/to/redis.conf
1:M 26 Jun 2024 20:22:22.312 * monotonic clock: POSIX clock_gettime
1:M 26 Jun 2024 20:22:22.313 * Running mode=standalone, port=6379.
1:M 26 Jun 2024 20:22:22.313 * Server initialized
1:M 26 Jun 2024 20:22:22.313 * Ready to accept connections tcp
```

The logs will be different depending on the container being used, but here we see that these logs are coming from Redis and it is ready to accept connections.

### Store data in Redis

Redis is a key-value cache, so it allows for very quick reads and writes. Let's store some data in Redis.

Read the following command like: 
> docker Execute interactive (-i) with a real shell (-t) redis (container name) redis-cli (command to run inside container) SET myname Andrew (arguments for the command ie. redis-cli)


```bash
docker exec -it redis redis-cli SET myname Andrew
```

Here we are using the `redis-cli` to interact with the redis cache inside of a container named `redis`.  Which should output: 
```
OK
```

This is the response from Redis, telling us that the data was stored successfully.

### Get data from Redis

Retrieving the data we put into redis is just as easy as storing it. 

```bash
docker exec -it redis redis-cli GET myname
```

Which should output: 
```
"Andrew"
```

### Stop Redis container
```bash
docker stop redis
```

This should output the container name that was stopped.

```
redis
```

The container is no longer running, but the data is still stored in the container until we remove it. We can see the stopped container using `docker ps -a` which will show all containers, running and stopped.

### Try to get data again

```bash
docker exec -it redis redis-cli GET myname
```

```
Error response from daemon: Container <id> is not running
```

### Start the stopped Redis container

It's easy enough to start the container, we just need to issue the start command against the container name (or the id of the container works too).

```bash
docker start redis
```

This should output the container name that was started.

```
redis
```

### Try to get data again (data is preserved)

When you try to get the data again, this time, we see that the data is still there.

```bash
docker exec -it redis redis-cli GET myname
```

Which should output: 
```
"Andrew"
```

### Remove Redis container

Finally, remove the container which will destroy the data inside of redis and remove the container from `docker ps`.

> Remember to stop the container before attempting to removing!

```bash
docker stop redis && docker rm redis
```

This should output the container name that was killed.

```
redis
```

### Recreate and see that the data doesn't exist anymore

Now we are going to create the container, this time with the `--rm` option which will remove the container when it's stopped.

Once it's started, we will attempt to get the data again. Either way, we stop the container when we are done with it (which will destroy the container).

```bash
docker run --rm --name redis -d valkey/valkey:8-alpine && docker exec -it redis redis-cli GET myname; docker stop redis;
```

Which should output: 
``` 
<the new container id>
(nil) <------- this is us trying to get the data again, and it no longer exists

redis
```

## Using [Docker Volumes](https://docs.docker.com/storage/volumes/) to preserve container data

In modern container orchestration technologies such as Kubernetes or Docker-Swarm, it's extremely common for containers to be removed and replaced with a different container. These two containers will have different ids, but they run the same application. As we just saw, when a container is removed it's data is also removed... so how can we make sure that the Redis data isn't deleted when the container is deleted?

> Docker Volumes allow you to map directories and files from the host os into the container os. 

### Create Redis data volume

Run the open-source image redis image (last arg), call it 'redis' (--name redis) and run it in detached mode (-d)

```bash
docker volume create redis_data
```

This should output the volume id, which is a unique identifier for the volume.

```
redis_data
```

### Recreate Redis container, using a docker volume

Run the open-source image redis image (last arg), call it 'redis' (--name redis) and run it in detached mode (-d) with volume 'redis_data'

```bash
docker run -v redis_data:/data --name redis -d valkey/valkey:8-alpine 
```

This should output the container id, which is a unique identifier for the container. For example:

```
51a331d26da6d0722fce95956ba52619a11b4870c0016df496a963f3c3641c68
```

### Enter Redis container, using interactive session

Let's create some data, then exit the container.

```bash
docker exec -it redis redis-cli
```

Which will take you into the redis-cli shell. Run these commands:

```
127.0.0.1:6379> SET myname Andrew
OK
127.0.0.1:6379> SET moredata potato
OK
127.0.0.1:6379> exit
```

Then exit the container. Validate that our new data is present by running:

```bash
docker exec -it redis redis-cli GET moredata
```

Which should output:

```text
"Potato
```

Now let's go back into the container and run these commands manually.

```bash
docker exec -it redis redis-cli
```

Which will take you back into the redis-cli shell. Run these commands to validate that the data still exists:

```
127.0.0.1:6379> GET myname
"Andrew"
127.0.0.1:6379> GET moredata
"potato"
127.0.0.1:6379> exit
```

### Delete Redis container

So now that we have written some data to the container that is backed by a volume, let's go ahead and stop and remove it:

```bash
docker stop redis && docker rm redis
```

This should output the container name that was stopped and killed.

```
redis
redis
```

### Recreate the Redis container, using the same docker volume

```bash
docker run -v redis_data:/data --name redis -d valkey/valkey:8-alpine
```

```
<id>
```

### Validate data persistence

```bash
docker exec -it redis redis-cli GET myname
```

```
"Andrew"
```

This is one of the most fundamental concepts of Docker. By using volumes, you can ensure that your data is preserved even when the container is removed. This is extremely useful for databases, caches, and other stateful applications.

## Create custom Docker images

Let's create a container to utilize the code in `redis_client_app/redis_client.py`. Our image is going to look very similar to the one we viewed earlier. With [Dockerfiles](/redis_client_app/Dockerfile), it's extremely important to put the things that change _least_ at the top, as Docker will build and cache the `layers` it generates from this file. This is so that on subsequent builds, you won't need to wait for the entire command again (unless you explicitly want to run it without cache, which is possible). 

```Docker
# syntax=docker/dockerfile:1
FROM python:3.13-slim-trixie AS builder
WORKDIR /build
COPY requirements.txt requirements.txt
RUN pip wheel --wheel-dir /wheels -r requirements.txt

FROM python:3.13-slim-trixie
WORKDIR /app
COPY requirements.txt requirements.txt
COPY --from=builder /wheels /wheels
RUN pip install --no-index --find-links=/wheels -r requirements.txt && rm -rf /wheels
COPY . .
RUN useradd --system --uid 1001 --create-home app && chown -R app:app /app
USER app
ENTRYPOINT [ "python3", "redis_client.py"]
```

Using this image, we can build a container that can run our app on almost any machine with that has Docker installed. 

> Question to think about: Why would we copy over the requirements file first, before copying over the rest of the app?

### Build our image

Build our container and tag (name) it as "bootcamp". The `redis_client_app` tells docker what context to use for building the image. In this case we want to be inside of the folder that has our code.

```bash
docker build -f redis_client_app/Dockerfile -t bootcamp redis_client_app
```

Optional: build a production-style distroless runtime image for smaller attack surface:

```Docker
# Final stage example
FROM gcr.io/distroless/python3-debian12
WORKDIR /app
COPY --from=builder /wheels /wheels
COPY . .
ENTRYPOINT ["python3", "redis_client.py"]
```

If you are on Apple Silicon, test multi-arch builds with BuildKit:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t bootcamp:2026 redis_client_app
```

Let's run our code without arguments to see what it can do

### Run our image

```bash
docker run bootcamp
```

Which should output:
```
NAME
    redis_client.py

SYNOPSIS
    redis_client.py COMMAND

COMMANDS
    COMMAND is one of the following:

     store_data

     get_data

     check_redis
```

#### Run our image with a different `CMD`
Alright now that our container is running, let's just make sure we can connect to Redis with `check_redis`.

```bash
docker run bootcamp check_redis
```

Which should output something like:
```
...
  File "/usr/local/lib/python3.8/site-packages/redis/connection.py", line 1192, in get_connection
    connection.connect()
  File "/usr/local/lib/python3.8/site-packages/redis/connection.py", line 563, in connect
    raise ConnectionError(self._error_message(e))
redis.exceptions.ConnectionError: Error -2 connecting to redis:6379. Name or service not known.
```

> Doh! What's going on? Well remember how everything is isolated, this is actually a good thing. You need to explicitly tell docker that these containers can communicate with eachother. To do this, we need to create a Docker Network.

### Connect Docker Containers

#### docker network create
Create a docker network to act as an network environment for multiple containers.

```bash
docker network create bootcamp_net --attachable
```

This should output the network id, which is a unique identifier for the network.

```
<id>
```

#### docker network connect
Okay now that we have a network, let's attach our redis container to it.

```bash
docker network connect bootcamp_net redis --alias redis
```

#### docker inspect redis
Not the greatest output for this command so let's check it manually. 

```bash
docker inspect redis
```

```
...
            "IPv6Gateway": "",
            "MacAddress": "",
            "Networks": {
                "bootcamp_net": {
                    "IPAMConfig": {},
                    "Links": null,
                    "Aliases": [
                        "redis",
...
```

#### docker run --net
That's what we're looking for. Okay cool, now we need to run our container with this network as well.

```bash
docker run --net bootcamp_net bootcamp check_redis
```

```
True
```

### Talking to Redis
Yay! Now we can connect to redis from our other container. Let's check on that data from earlier:

#### Run a single command
```bash
docker run -it --net  bootcamp_net bootcamp get_data myname
```

```
The data is in redis!
key='myname'
val='Andrew'
```

#### Run a command that creates a shell
We can also store new data using an interactive shell (`-i`):

```bash
docker run -it --net  bootcamp_net bootcamp store_data
```

```
What should we call this data?
thebestfood
What is the data?
potato
The data has been stored in redis
 ```

##### Validate the stored data
Now let's check for that new data:

```bash
docker run -it --net  bootcamp_net bootcamp get_data thebestfood
```

```
The data is in redis!
key='thebestfood'
val='potato'
```

There you have it! We just created a python application that is talking to our redis container and using it as our cache. In the real world, you would build more complex applications that use this cache to store and retrieve data.

> Hopefully through this exercise you can see that docker can unlock some amazing development power, while remaining a secure platform to build and run containers from.

#### Let's clean up after ourselves

Unless you are running a large application in Docker, it's easy to forget that you have containers running, so it's always a good idea to check on them and clean up after yourself.

```bash
docker stop redis && docker rm redis
docker stop bootcamp && docker rm bootcamp
docker network rm bootcamp_net
```

## Speeding things up with Docker Compose

So far it's kind of been a nightmare of cli commands. There has to be a better way right...?

There is! With docker compose, we can combine everything we've learned so far into a single file that's easier to manage.
### docker compose files

The `docker-compose.yml` file has it's own syntax, syntax verions, and a [ton of useful tools](https://docs.docker.com/compose/compose-file/compose-file-v3/) that we won't have time to go over here.

Here's what [a docker-compose.yml file](/redis_client_app/docker-compose.yml) looks like: 

```bash
# Create the network so that our containers can talk to each-other
networks:
    redis:
      name: redis_net
      driver: bridge

# Create the storage volume for redis
volumes: 
    redis_storage:
        name: redis_storage

# Define our containers
services:

    # Define redis properties
    cache:
        image: 'valkey/valkey:8-alpine'
        volumes: 
            - redis_storage:/data
        networks:
            - redis

    # Define python app properties, have it build our image
    app:
        build: 
            context: .
        networks: 
            - redis
        entrypoint: "/bin/sh"
        tty: true
        healthcheck:
            test: ["CMD", "python", "redis_client.py", "check_redis"] 
            interval: 3s
```

### docker compose cli

#### docker compose up
The following command will create the network, the volume, both containers (in the background), and the proper links:

```bash
cd redis_client_app && docker compose up -d --build
```

For live development in Compose v2.22+, run watch mode in a separate terminal:

```bash
docker compose watch
```

```
...
Starting redis_app_1   ... done
Starting redis_cache_1 ... done
```

#### docker compose ps
Let's check on it! Run the following command to see the status of everything:

```bash
docker compose ps
```

```
    Name                   Command                  State        Ports  
------------------------------------------------------------------------
redis_app_1     /bin/sh                          Up (healthy)           
redis_cache_1   docker-entrypoint.sh redis ...   Up             6379/tcp
```

> The `Healthy` status above indicates that the command we defined as the healthcheck is returning without failing.

##### Side note

Most docker-contains have some type of shell that you can use to run commands with. In this case, the command we want to run will open up a new shell instance `/bin/sh` and attach us to it so that it acts as our new shell. When we are done, we exit it with `exit`. You could replace `/bin/sh` with any valid executable in the `$PATH` environment variable. For example, listing the files in the `WORKDIR` directory of a container:

```bash
docker compose exec app ls -lrt
```

```
total 16
-rw-r--r-- 1 root root   48 Jun 21 18:56 requirements.txt
-rw-r--r-- 1 root root  361 Jun 21 20:46 Dockerfile
-rw-r--r-- 1 root root  797 Jun 21 23:04 docker-compose.yml
-rw-r--r-- 1 root root 1094 Jun 21 23:06 redis_client.py
```

#### docker compose exec
Now let's run our commands again, this time from inside the container! The following command will attach us to the python container so that we can run the same commands as before. We read this command like so: `docker execute <service_name> <command_inside_container>`.

```bash
docker compose exec app /bin/sh
```

##### Living inside a container
Now you are inside the container, feel free to take a look around. When you are ready, run the `ENTRYPOINT` command:

```
python redis_client.py
```

```
NAME
    redis_client.py

SYNOPSIS
    redis_client.py COMMAND

COMMANDS
    COMMAND is one of the following:

     store_data

     get_data

     check_redis

```

```bash
python redis_client.py check_redis
```

```
True
```

Exit the container context by typing:

```bash
exit
```

#### Or you can just run the app directly

```bash
docker compose exec app python redis_client.py
```

#### docker compose up --scale

Using the scale command, we are able to easily spin up more containers of the same type. This is useful for load balancing, or for testing purposes. It's also a great way to see how your application will behave in a distributed environment. There are a lot of things to consider when scaling, but for now, let's just see how it works.

```bash
docker compose up -d --scale cache=2
```
   
And now we can see the new container spinning up:
 
```text
[+] Running 1/2
 ✔ Container redis-cache-1  Running                                                                                                                                                                                                                                                                       0.0s 
 ⠹ Container redis-cache-2  Started
```

or if you want to go crazy:

```bash
docker compose up -d --scale cache=10
```

```text
>
[+] Running 1/10
 ✔ Container redis-cache-1   Running                                                                                                                                                                                                                                                                      0.0s 
 ⠼ Container redis-cache-10  Started                                                                                                                                                                                                                                                                      1.5s 
 ⠼ Container redis-cache-2   Started                                                                                                                                                                                                                                                                      1.5s 
 ⠼ Container redis-cache-4   Started                                                                                                                                                                                                                                                                      1.5s 
 ⠼ Container redis-cache-3   Started                                                                                                                                                                                                                                                                      1.5s 
 ⠼ Container redis-cache-6   Started                                                                                                                                                                                                                                                                      1.5s 
 ⠼ Container redis-cache-8   Started                                                                                                                                                                                                                                                                      1.5s 
 ⠼ Container redis-cache-9   Started                                                                                                                                                                                                                                                                      1.5s 
 ⠼ Container redis-cache-7   Started                                                                                                                                                                                                                                                                      1.5s 
 ⠼ Container redis-cache-5   Started 
```

Why is this useful? Well, if you have a lot of jobs to do, you can spin up a lot of workers to do them. If you have a lot of traffic, you can spin up a lot of web servers to handle it. If you have a lot of data, you can spin up a lot of databases to store it. 

#### docker compose logs

Using the logs command of docker compose, we can see the logs of all the containers in the docker compose file.

```bash
docker compose logs
```

```text
cache-10  | 1:M 26 Jun 2024 23:30:07.599 * Ready to accept connections tcp
cache-1   | 1:M 26 Jun 2024 23:30:03.715 * monotonic clock: POSIX clock_gettime
cache-3   | 1:C 26 Jun 2024 23:30:07.733 # Warning: no config file specified, using the default config. In order to specify a config file use redis-server /path/to/redis.conf
cache-3   | 1:M 26 Jun 2024 23:30:07.733 * monotonic clock: POSIX clock_gettime
...
cache-6   | 1:M 26 Jun 2024 23:30:06.811 * Done loading RDB, keys loaded: 2, keys expired: 0.
cache-3   | 1:M 26 Jun 2024 23:30:07.734 * RDB memory usage when created 0.83 Mb
cache-3   | 1:M 26 Jun 2024 23:30:07.734 * Done loading RDB, keys loaded: 2, keys expired: 0.
cache-3   | 1:M 26 Jun 2024 23:30:07.734 * DB loaded from disk: 0.000 seconds
cache-3   | 1:M 26 Jun 2024 23:30:07.734 * Ready to accept connections tcp
cache-6   | 1:M 26 Jun 2024 23:30:06.811 * DB loaded from disk: 0.001 seconds
cache-6   | 1:M 26 Jun 2024 23:30:06.811 * Ready to accept connections tcp
```

Just view the logs for a single service:

```bash
docker compose logs cache
```

```text
...
cache-1  | 22:C 26 Jun 2024 23:07:31.080 * DB saved on disk
cache-2  | 1:C 26 Jun 2024 23:08:22.961 * oO0OoO0OoO0Oo Redis is starting oO0OoO0OoO0Oo
...
```

#### docker compose stats

```bash
docker compose stats
```

Which will take over your console and show you the stats of the containers in the docker compose file.

```text
           Name                         CPU               Memory            PIDs
        ---------------------------------------------------------------------------
        <stats about your services appear here>
```

Type control-c to exit the stats view.

#### docker compose top

```bash
docker compose top
```

Which will show you the top processes running in each container.

```text
redis-app-1
UID    PID     PPID    C    STIME   TTY   TIME       CMD
root   80731   80713   0    22:59   ?     00:00:00   /bin/sh   

redis-cache-1
UID   PID     PPID    C    STIME   TTY   TIME       CMD
999   79610   79578   0    22:57   ?     00:00:01   redis-server *:6379   

redis-cache-2
UID   PID     PPID    C    STIME   TTY   TIME       CMD
999   85169   85150   0    23:08   ?     00:00:00   redis-server *:6379 

...
```

#### docker compose events

To see what is happening with your containers, you can use the events command.
    
```bash
docker compose events
```

This will show the `HEALTHCHECK` in the compose file running over and over again. To exit, type control-c.

#### Wrapping up

Let's make sure everything still works:

```bash
docker compose exec app python redis_client.py check_redis
```

This should output True.

#### docker compose down
To bring all the containers down, type: 

Exit the container context by typing:

```bash
docker compose down
```

> As you can see, docker compose drastically reduces development time while allowing the same features as the CLI.

## Incorporating Visual Studio Code 

IDEs like PyCharm and Visual Studio Code can make use of docker to provide a fresh development environment for all people on your team.

### Installing

#### Mac Users

Install Brew (if needed):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Have Brew install VSCode

```bash
brew install --cask visual-studio-code
```

#### Windows Users

Install from this link: https://code.visualstudio.com/download

### Install VSCode dependencies

1. Run VSCode
2. Open the `Extensions` section of VSCode
3. Install the Docker extension (ms-azuretools.vscode-docker)
4. Install the Remote-Containers extension (ms-vscode-remote.remote-containers)

### Build & Run our development container

```bash
docker compose build
```

```
...
 => => exporting layers                                                                                                                                                                                                                                                                                            0.0s
 => => writing image sha256:3cf82f189fc4a35542fc08a1663fe35a4f2e7262db398e041fa3c16839f7af57                                                                                                                                                                                                                       0.0s
 => => naming to docker.io/library/redis_app
```

If we put this image name in our `.devcontainer/devcontainer.json` file, we are able to use this image as a development environment.

Now in VSCode, in the bottom left, we should see a green button that looks like two arrows. Click on this button and find `Reopen in Containers...` in the dropdown and select it. A new window will pop-up to provide an isolated development environment.

### Run our Python code inside the container
1. Click on the `Run and Debug` section in VSCode
2. Click on the `Run` button and you should see output similar to:
```bash
root@a368d1296c1e:/workspaces/2024-Bootcamp-Docker#  cd /workspaces/2024-Bootcamp-Docker ; /usr/bin/env /usr/local/bin/python /root/.vscode-server/extensions/ms-python.python-2022.8.1/pythonFiles/lib/python/debugpy/launcher 46805 -- redis_client_app/redis_client.py hello_world 
Oh hai
```
3. If you want to experiement more, add a breakpoint to the hello_world method and it should stop on that line next time you run.

How does this work? VSCode has a `.vscode/launch.json` file that you can add run configurations into. This is extremely powerful and dynamic and will allow you to run most workloads right in VSCode.

## Container Security Checks with Docker Scout

Before pushing an image, run a quick vulnerability check:

```bash
docker scout quickview bootcamp:2026
docker scout cves bootcamp:2026
docker scout recommendations bootcamp:2026
```

This gives you a simple 2026 workflow: build, scan, and then ship.

## Final Thoughts

By going through this exercise, you should have a better idea of what Docker is and what kinds of things you can do with it. There is so much more to explore, here are just a few things that i've found fun while working with it:

- You can run Docker inside Docker (woah).
  - Very useful for CI/CD, since the runner can be containerized but it can also create other containers.
- Orchestrating container deployments with docker compose using docker-swarm.
- *Using PyCharm to have your default interpreter be inside of a container*
  - Allows for a clean development environment on ever build
  - Debugging features still work
  - Easily test across python versions, by using a different base image for each build/test
  - More info: https://www.jetbrains.com/help/pycharm/using-docker-compose-as-a-remote-interpreter.html

I strongly believe that containers are the future, so this knowledge is going to be foundational before long. Any time you need to try out a new service, tool, platform, etc. check if a docker image exists for it. 