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

Let's look at Valkey, a popular open-source key-value store and caching solution.

### What is Valkey?

Valkey is an in-memory key-value data store used as a database, cache, streaming engine, and message broker. It's a Linux Foundation fork of Redis (started in 2024 after Redis Inc. moved to a non-OSI license) that stays BSD-licensed and is a drop-in replacement — same wire protocol, same `redis-cli`, same Python client.

On my team, we use a library called [`RQ-Python`](https://python-rq.org) that builds a queuing system for Python jobs on top of a Redis-compatible store like Valkey. We create thousands of jobs each night and have hundreds of worker containers that perform the jobs.

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
REPOSITORY      TAG        IMAGE ID       CREATED       SIZE
valkey/valkey   8-alpine   0b0c4e62c113   8 days ago    42MB
```

What does this tell us? Well we are using the `8-alpine` tag which is a slim, Alpine Linux variant of Valkey 8. The `IMAGE ID` is a unique identifier for the image, and the `SIZE` is the size of the image on disk.

In this example, we can see that this image was built 8 days ago and is only 42MB in size — much smaller than a typical Debian-based image.

### Create a cache container

> Run the Valkey image (last arg), call it 'cache' (--name cache) and run it in detached mode (-d)

```bash
docker run --name cache -d valkey/valkey:8-alpine
```

This should spit out the docker image id, which is a unique identifier for the container. That's literally how easy it can be to run a Docker image.

### Expose the cache to your host (`-p`)

By default, the container listens on port 6379 — but only inside Docker's internal network. Your laptop can't reach it. To open a path from your host into the container, use `-p HOST_IP:HOST_PORT:CONTAINER_PORT`. Bind to loopback (`127.0.0.1`) so the port is reachable from your machine but not from the wider network:

```bash
docker rm -f cache
docker run --name cache -p 127.0.0.1:6379:6379 -d valkey/valkey:8-alpine
docker ps --filter name=cache --format "table {{.Names}}\t{{.Ports}}"
```

Notice the `PORTS` column now shows the host binding:

```
NAMES     PORTS
cache     127.0.0.1:6379->6379/tcp
```

Now your host can talk to Valkey on `localhost:6379`. We can prove it by running another disposable container that connects through your host's network bridge:

```bash
docker run --rm valkey/valkey:8-alpine redis-cli -h host.docker.internal ping
```

```
PONG
```

> **When to expose more broadly:** the shorter `-p 6379:6379` form binds to `0.0.0.0` and exposes the port on every interface — useful when another machine on your LAN actually needs to connect, but easy to leak on coffeeshop wifi. Default to loopback and broaden deliberately.

### View container in container list

> Check the status of the container

```bash
docker ps
```

This should output something like: 
```
CONTAINER ID   IMAGE                    COMMAND                  CREATED          STATUS          PORTS      NAMES
16ad2cca6925   valkey/valkey:8-alpine   "docker-entrypoint.s…"   22 seconds ago   Up 21 seconds   6379/tcp   cache
```

There's our docker container running with Valkey inside of it. The `STATUS` column tells us that the container is `Up` and has been running for 21 seconds. The `PORTS` column tells us that the container is listening on port `6379`.

### Check container logs
```bash
docker logs cache
```

Which outputs: 
```
1:M 15 May 2026 00:22:12.779 * oO0OoO0OoO0Oo Valkey is starting oO0OoO0OoO0Oo
1:M 15 May 2026 00:22:12.779 * Valkey version=8.1.7, bits=64, commit=00000000, modified=0, pid=1, just started
1:M 15 May 2026 00:22:12.779 # Warning: no config file specified, using the default config. In order to specify a config file use valkey-server /path/to/valkey.conf
1:M 15 May 2026 00:22:12.779 * monotonic clock: POSIX clock_gettime
1:M 15 May 2026 00:22:12.779 * Running mode=standalone, port=6379.
1:M 15 May 2026 00:22:12.779 * Server initialized
1:M 15 May 2026 00:22:12.780 * Ready to accept connections tcp
```

The logs will be different depending on the container being used, but here we see that Valkey is ready to accept connections.

### Store data in the cache

Valkey (like Redis) is a key-value cache, so it allows for very quick reads and writes. Let's store some data.

Read the following command like: 
> docker Execute interactive (-i) with a real shell (-t) cache (container name) redis-cli (command to run inside container) SET myname Andrew (arguments for the command ie. redis-cli)


```bash
docker exec -it cache redis-cli SET myname Andrew
```

Here we are using `redis-cli` (the CLI tool that Valkey ships) to interact with the cache inside a container named `cache`. Which should output: 
```
OK
```

This is the response from the cache, telling us that the data was stored successfully.

### Get data from the cache

Retrieving the data we put into the cache is just as easy as storing it. 

```bash
docker exec -it cache redis-cli GET myname
```

Which should output: 
```
"Andrew"
```

### Stop the cache container
```bash
docker stop cache
```

This should output the container name that was stopped.

```
cache
```

The container is no longer running, but the data is still stored in the container until we remove it. We can see the stopped container using `docker ps -a` which will show all containers, running and stopped.

### Try to get data again

```bash
docker exec -it cache redis-cli GET myname
```

```
Error response from daemon: Container <id> is not running
```

### Start the stopped cache container

It's easy enough to start the container, we just need to issue the start command against the container name (or the id of the container works too).

```bash
docker start cache
```

This should output the container name that was started.

```
cache
```

### Try to get data again (data is preserved)

When you try to get the data again, this time, we see that the data is still there.

```bash
docker exec -it cache redis-cli GET myname
```

Which should output: 
```
"Andrew"
```

### Remove the cache container

Finally, remove the container which will destroy the data inside the cache and remove the container from `docker ps`.

> Remember to stop the container before attempting to removing!

```bash
docker stop cache && docker rm cache
```

This should output the container name that was killed.

```
cache
```

### Recreate and see that the data doesn't exist anymore

Now we are going to create the container, this time with the `--rm` option which will remove the container when it's stopped.

Once it's started, we will attempt to get the data again. Either way, we stop the container when we are done with it (which will destroy the container).

```bash
docker run --rm --name cache -d valkey/valkey:8-alpine && docker exec -it cache redis-cli GET myname; docker stop cache;
```

Which should output: 
``` 
<the new container id>
(nil) <------- this is us trying to get the data again, and it no longer exists

cache
```

## Telling Docker how to behave (resources & restart)

So far we've trusted Docker's defaults. That's fine on a laptop where one runaway container at most ruins your afternoon. In production, you want explicit limits and recovery rules. Let's look at the three flags that bridge "works on my laptop" to "runs anywhere": `--memory`, `--cpus`, and `--restart`.

### Memory and CPU caps (`--memory`, `--cpus`)

Without limits, a container can consume every byte of RAM and every CPU cycle on the host. That's how one misbehaving service takes down everything else on the box. Cap it:

```bash
docker rm -f cache
docker run --name cache --memory 64m --cpus 0.5 -d valkey/valkey:8-alpine
docker stats --no-stream cache
```

```
CONTAINER ID   NAME      CPU %     MEM USAGE / LIMIT   MEM %     NET I/O         BLOCK I/O   PIDS
61f1e97c6d75   cache     0.35%     12.72MiB / 64MiB    19.88%    1.17kB / 126B   0B / 0B     5
```

The `MEM USAGE / LIMIT` column shows our 64 MiB ceiling, and `--cpus 0.5` means at most half a CPU core's worth of work. If the container tries to allocate past the memory limit, the Linux OOM killer terminates the process inside — Docker's cgroups enforce this at the kernel level.

### Bring it back when it falls (`--restart`)

What if your process crashes? By default, the container exits and stays dead. The `--restart` flag tells Docker to bring it back automatically:

```bash
docker rm -f cache
docker run --name cache --restart unless-stopped -d valkey/valkey:8-alpine

# Simulate a crash by telling Valkey to shut itself down ungracefully
docker exec cache redis-cli SHUTDOWN NOSAVE || true
sleep 3
docker ps --filter name=cache --format "table {{.Names}}\t{{.Status}}"
docker inspect cache --format 'RestartCount={{.RestartCount}}'
```

```
NAMES     STATUS
cache     Up 2 seconds
RestartCount=1
```

The container died and Docker brought it back. `RestartCount=1` is your proof. The four restart policies:

- `no` — never restart (default).
- `on-failure[:N]` — restart only on non-zero exit, optionally bounded to N retries.
- `always` — restart no matter what, including when the Docker daemon starts.
- `unless-stopped` — like `always`, but if you ran `docker stop cache` yourself, it stays stopped across daemon restarts. **This is usually the one you want.**

> **Heads up:** `docker kill` is treated as user intent in Docker Desktop and does *not* trigger a restart. To test the policy, simulate a real crash from inside the container (like the `SHUTDOWN NOSAVE` above).

> **Coming up:** the third runtime flag — `-e` for injecting environment variables — needs a custom image to demonstrate well, so we'll cover it once we've built one in the next chapter.

```bash
docker rm -f cache
```

## Using [Docker Volumes](https://docs.docker.com/storage/volumes/) to preserve container data

In modern container orchestration technologies such as Kubernetes or Docker-Swarm, it's extremely common for containers to be removed and replaced with a different container. These two containers will have different ids, but they run the same application. As we just saw, when a container is removed it's data is also removed... so how can we make sure that the cache data isn't deleted when the container is deleted?

> Docker Volumes allow you to map directories and files from the host os into the container os. 

### Create a data volume

```bash
docker volume create cache_data
```

This should output the volume name:

```
cache_data
```

### Recreate the cache container, using a docker volume

Run Valkey with volume `cache_data` mapped to `/data` inside the container:

```bash
docker run -v cache_data:/data --name cache -d valkey/valkey:8-alpine 
```

This should output the container id, which is a unique identifier for the container. For example:

```
51a331d26da6d0722fce95956ba52619a11b4870c0016df496a963f3c3641c68
```

### Enter the cache container, using interactive session

Let's create some data, then exit the container.

```bash
docker exec -it cache redis-cli
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
docker exec -it cache redis-cli GET moredata
```

Which should output:

```text
"Potato
```

Now let's go back into the container and run these commands manually.

```bash
docker exec -it cache redis-cli
```

Which will take you back into the redis-cli shell. Run these commands to validate that the data still exists:

```
127.0.0.1:6379> GET myname
"Andrew"
127.0.0.1:6379> GET moredata
"potato"
127.0.0.1:6379> exit
```

### Delete the cache container

So now that we have written some data to the container that is backed by a volume, let's go ahead and stop and remove it:

```bash
docker stop cache && docker rm cache
```

This should output the container name that was stopped and killed.

```
cache
cache
```

### Recreate the cache container, using the same docker volume

```bash
docker run -v cache_data:/data --name cache -d valkey/valkey:8-alpine
```

```
<id>
```

### Validate data persistence

```bash
docker exec -it cache redis-cli GET myname
```

```
"Andrew"
```

This is one of the most fundamental concepts of Docker. By using volumes, you can ensure that your data is preserved even when the container is removed. This is extremely useful for databases, caches, and other stateful applications.

## Create custom Docker images

Let's create a container to utilize the code in `redis_client_app/cache_client.py`. Our image is going to look very similar to the one we viewed earlier. With [Dockerfiles](/redis_client_app/Dockerfile), it's extremely important to put the things that change _least_ at the top, as Docker will build and cache the `layers` it generates from this file. This is so that on subsequent builds, you won't need to wait for the entire command again (unless you explicitly want to run it without cache, which is possible). 

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
ENTRYPOINT [ "python3", "cache_client.py"]
```

Using this image, we can build a container that can run our app on almost any machine with that has Docker installed. 

> Question to think about: Why would we copy over the requirements file first, before copying over the rest of the app?

### Build our image

Build our container and tag (name) it as "bootcamp". The trailing `redis_client_app` tells docker what context to use for building the image. In this case we want to be inside of the folder that has our code.

```bash
docker build -f redis_client_app/Dockerfile -t bootcamp redis_client_app
```

### Build it again — meet the layer cache

Run the exact same `docker build` again. It should finish in under a second:

```bash
docker build -f redis_client_app/Dockerfile -t bootcamp redis_client_app
```

```
#8 [builder 4/4] RUN pip install --upgrade pip && pip wheel --wheel-dir /wheels -r requirements.txt
#8 CACHED
#9 [stage-1 4/7] COPY --from=builder /wheels /wheels
#9 CACHED
#10 [stage-1 6/7] COPY . .
#10 CACHED
#11 [stage-1 5/7] RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt && rm -rf /wheels
#11 CACHED
...
```

Every step says `CACHED`. Docker fingerprints the inputs to each `Dockerfile` instruction and reuses the resulting layer if nothing changed. Now edit a source file and rebuild:

```bash
# pretend you fixed a typo in cache_client.py
echo '# tweak' >> redis_client_app/cache_client.py
docker build -f redis_client_app/Dockerfile -t bootcamp redis_client_app
```

```
#8 [builder 4/4] RUN pip install --upgrade pip && pip wheel --wheel-dir /wheels -r requirements.txt
#8 CACHED
#9 [stage-1 5/7] RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt && rm -rf /wheels
#9 CACHED
#10 [stage-1 6/7] COPY . .
#10 DONE 0.0s
#11 [stage-1 7/7] RUN useradd --system --uid 1001 --create-home app && chown -R app:app /app
#11 DONE 0.1s
```

The expensive dependency layers are still `CACHED`, but `COPY . .` and everything below it re-ran. That's why we copy `requirements.txt` and install dependencies *before* `COPY . .` — so editing your code doesn't reinstall the world.

Now bust the dependency cache by touching `requirements.txt`:

```bash
echo "" >> redis_client_app/requirements.txt
docker build -f redis_client_app/Dockerfile -t bootcamp redis_client_app
```

```
#10 [stage-1 3/7] COPY requirements.txt requirements.txt
#10 DONE 0.0s
#11 [builder 3/4] COPY requirements.txt requirements.txt
#11 DONE 0.0s
#12 [builder 4/4] RUN pip install --upgrade pip && pip wheel --wheel-dir /wheels -r requirements.txt
#12 0.834 Collecting redis==6.4.0 ...
#12 DONE 6.1s
```

Now the wheel build runs from scratch — that's the multi-second cost we usually skip. **The order of `Dockerfile` instructions is your cache hit-rate.** Put what changes least at the top.

> **Pro tip:** `--no-cache` forces a clean rebuild. Useful when you suspect cached layers are masking a bug, but slow — only reach for it deliberately.

Before moving on, revert the demo edits so your working tree is clean:

```bash
# Drop the trailing comment we appended and the blank line in requirements.txt
sed -i.bak -e '${/^# tweak$/d;}' redis_client_app/cache_client.py && rm redis_client_app/cache_client.py.bak
sed -i.bak -e '${/^$/d;}' redis_client_app/requirements.txt && rm redis_client_app/requirements.txt.bak
```

### Send less to the build daemon (`.dockerignore`)

When you run `docker build`, Docker first packages up the *build context* — the entire directory you pointed at — and ships it to the build engine. Look at what gets shipped:

```bash
du -sh redis_client_app
```

```
20K	redis_client_app
```

20 KB is fine. But if you had a `.git` folder, a `.venv` with hundreds of MB of installed packages, or local test data, all of it would be sent on every single build, even if your `Dockerfile` doesn't `COPY` it. Worse, files like `.env` with secrets could leak into your image if you ever wrote `COPY . .`.

Solution: a `.dockerignore` file alongside your `Dockerfile`. Same syntax as `.gitignore`. Ours:

```bash
cat redis_client_app/.dockerignore
```

```
.git
.gitignore
__pycache__/
*.pyc
.venv/
venv/
tests/
```

Anything matching these patterns is skipped when building the context. Treat `.dockerignore` as a defensive habit — you almost never want `.git`, virtualenvs, or local credentials inside your build context.

### Why two `FROM`s? Multi-stage builds

Look back at the Dockerfile. There are *two* `FROM python:3.13-slim-trixie` lines: the first is named `AS builder`, the second is the final image. That's a **multi-stage build** — and it's the reason your image stays small.

The `builder` stage installs `pip`, downloads source distributions, and compiles wheels. That stage produces a `/wheels` directory. The final stage starts fresh from the slim base and copies just `/wheels` over with `COPY --from=builder`. The build toolchain — pip's caches, compiled C bindings' source files, intermediate downloads — stays in the builder stage and is **discarded**. Only the final stage becomes your image.

Compare sizes:

```bash
docker images bootcamp
docker images python:3.13-slim-trixie
```

```
REPOSITORY   TAG       SIZE
bootcamp     latest    163MB

REPOSITORY   TAG                SIZE
python       3.13-slim-trixie   143MB
```

Our app image is only ~20 MB heavier than the bare Python base. A naive single-stage `FROM python:3.13 + RUN pip install` build typically lands at 1+ GB because the full Python image plus pip's caches stick around. Multi-stage is how you ship lean images without rewriting in Go.

Optional: build a production-style distroless runtime image for smaller attack surface:

```Docker
# Final stage example
FROM gcr.io/distroless/python3-debian12
WORKDIR /app
COPY --from=builder /wheels /wheels
COPY . .
ENTRYPOINT ["python3", "cache_client.py"]
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
    cache_client.py

SYNOPSIS
    cache_client.py COMMAND

COMMANDS
    COMMAND is one of the following:

     store_data

     get_data

     check_cache
```

#### Run our image with a different `CMD`
Alright now that our container is running, let's just make sure we can connect to our cache with `check_cache`.

```bash
docker run bootcamp check_cache
```

Which should output something like:
```
...
  File "/usr/local/lib/python3.8/site-packages/redis/connection.py", line 1192, in get_connection
    connection.connect()
  File "/usr/local/lib/python3.8/site-packages/redis/connection.py", line 563, in connect
    raise ConnectionError(self._error_message(e))
redis.exceptions.ConnectionError: Error -2 connecting to cache:6379. Name or service not known.
```

> Doh! What's going on? Well remember how everything is isolated, this is actually a good thing. You need to explicitly tell docker that these containers can communicate with eachother. To do this, we need to create a Docker Network.

#### Override config via `-e` (the runtime flag we deferred)

Before we wire up the network, look closer at that error: it says `connecting to cache:6379`. Where did `cache` come from? It's the default in the Python code — `os.environ.get("CACHE_HOST", "cache")`. Apps shouldn't bake configuration into their image; they read it from environment variables, and `-e KEY=VALUE` is how you inject one at run time:

```bash
docker run --rm -e CACHE_HOST=somehost.invalid bootcamp check_cache 2>&1 | tail -3
```

```
  File "/usr/local/lib/python3.13/site-packages/redis/connection.py", line 397, in connect_check_health
    raise ConnectionError(self._error_message(e))
redis.exceptions.ConnectionError: Error -2 connecting to somehost.invalid:6379. Name or service not known.
```

The error now references `somehost.invalid` — proof that our injected value won. This pattern is how one image works in dev, staging, and prod: you change the env, the image stays the same. Pass `-e` multiple times for multiple variables, or `--env-file path/to/.env` to load a whole file at once.

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
Okay now that we have a network, let's attach our cache container to it.

```bash
docker network connect bootcamp_net cache --alias cache
```

#### docker inspect cache
Not the greatest output for this command so let's check it manually. 

```bash
docker inspect cache
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
                        "cache",
...
```

#### docker run --net
That's what we're looking for. Okay cool, now we need to run our container with this network as well.

```bash
docker run --net bootcamp_net bootcamp check_cache
```

```
True
```

### Talking to the cache
Yay! Now we can connect to the cache from our other container. Let's check on that data from earlier:

#### Run a single command
```bash
docker run -it --net  bootcamp_net bootcamp get_data myname
```

```
The data is in the cache!
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
The data has been stored in the cache
 ```

##### Validate the stored data
Now let's check for that new data:

```bash
docker run -it --net  bootcamp_net bootcamp get_data thebestfood
```

```
The data is in the cache!
key='thebestfood'
val='potato'
```

There you have it! We just created a python application that is talking to our cache container. In the real world, you would build more complex applications that use this cache to store and retrieve data.

> Hopefully through this exercise you can see that docker can unlock some amazing development power, while remaining a secure platform to build and run containers from.

#### Let's clean up after ourselves

Unless you are running a large application in Docker, it's easy to forget that you have containers running, so it's always a good idea to check on them and clean up after yourself.

```bash
docker stop cache && docker rm cache
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
    bootcamp:
      name: bootcamp_net
      driver: bridge

# Create the storage volume for our cache
volumes:
    cache_data:
        name: cache_data

# Define our containers
services:

    # Define cache properties
    cache:
        image: 'valkey/valkey:8-alpine'
        volumes:
            - cache_data:/data
        networks:
            - bootcamp

    # Define python app properties, have it build our image
    app:
        build:
            context: .
        networks:
            - bootcamp
        environment:
            CACHE_HOST: ${CACHE_HOST:-cache}
        entrypoint: "/bin/sh"
        tty: true
        healthcheck:
            test: ["CMD", "python", "cache_client.py", "check_cache"]
            interval: 3s
```

### Configuring with environment variables and `.env` files

Notice the `${CACHE_HOST:-cache}` in the `environment:` block above. That's compose's variable substitution syntax: read the value from a variable named `CACHE_HOST`, or fall back to the literal string `cache` if it's not set. You'll see this pattern everywhere in real compose files — it's how teams keep one compose file that works in dev, CI, and production.

Compose looks for variables in three places, in this order of priority:

1. **Your shell environment** — `CACHE_HOST=somehost docker compose up` overrides everything.
2. **`--env-file path/to/file`** — explicit file passed on the command line.
3. **A `.env` file** in the same directory as `docker-compose.yml` — auto-loaded if it exists.

You can preview exactly what compose will use by running `docker compose config`. It expands all variables and prints the fully-resolved YAML:

```bash
cd redis_client_app && docker compose config
```

```yaml
services:
  app:
    environment:
      CACHE_HOST: cache
    ...
```

The default kicked in because no `CACHE_HOST` was set anywhere. Override from the shell:

```bash
CACHE_HOST=somehost.invalid docker compose config | grep -A1 environment
```

```
    environment:
      CACHE_HOST: somehost.invalid
```

Or load from a file. Create `/tmp/bootcamp.env` with `CACHE_HOST=valkey` inside, then:

```bash
docker compose --env-file /tmp/bootcamp.env config | grep -A1 environment
```

```
    environment:
      CACHE_HOST: valkey
```

> **Practical note:** `.env` is for *non-secret* configuration like hostnames, ports, log levels. For real secrets (passwords, API keys), use Docker secrets — we'll show that pattern in Part 2.

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
 Container redis_client_app-cache-1  Started
 Container redis_client_app-app-1    Started
```

#### docker compose ps
Let's check on it! Run the following command to see the status of everything:

```bash
docker compose ps
```

```
NAME                         IMAGE                    COMMAND                  SERVICE   STATUS                   PORTS
redis_client_app-app-1       redis_client_app-app     "/bin/sh"                app       Up 8 seconds (healthy)
redis_client_app-cache-1     valkey/valkey:8-alpine   "docker-entrypoint.s…"   cache     Up 8 seconds            6379/tcp
```

> The `Healthy` status above indicates that the command we defined as the healthcheck is returning without failing.

##### Side note

Most docker-contains have some type of shell that you can use to run commands with. In this case, the command we want to run will open up a new shell instance `/bin/sh` and attach us to it so that it acts as our new shell. When we are done, we exit it with `exit`. You could replace `/bin/sh` with any valid executable in the `$PATH` environment variable. For example, listing the files in the `WORKDIR` directory of a container:

```bash
docker compose exec app ls -lrt
```

```
total 16
-rw-r--r-- 1 root root   48 May 14 18:56 requirements.txt
-rw-r--r-- 1 root root  604 May 14 20:46 Dockerfile
-rw-r--r-- 1 root root  900 May 14 23:04 docker-compose.yml
-rw-r--r-- 1 root root 1094 May 14 23:06 cache_client.py
```

#### docker compose exec
Now let's run our commands again, this time from inside the container! The following command will attach us to the python container so that we can run the same commands as before. We read this command like so: `docker execute <service_name> <command_inside_container>`.

```bash
docker compose exec app /bin/sh
```

##### Living inside a container
Now you are inside the container, feel free to take a look around. When you are ready, run the `ENTRYPOINT` command:

```
python cache_client.py
```

```
NAME
    cache_client.py

SYNOPSIS
    cache_client.py COMMAND

COMMANDS
    COMMAND is one of the following:

     store_data

     get_data

     check_cache

```

```bash
python cache_client.py check_cache
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
docker compose exec app python cache_client.py
```

#### docker compose up --scale

Using the scale command, we are able to easily spin up more containers of the same type. This is useful for load balancing, or for testing purposes. It's also a great way to see how your application will behave in a distributed environment. There are a lot of things to consider when scaling, but for now, let's just see how it works.

```bash
docker compose up -d --scale cache=2
```
   
And now we can see the new container spinning up:
 
```text
[+] Running 1/2
 ✔ Container redis_client_app-cache-1  Running
 ⠹ Container redis_client_app-cache-2  Started
```

or if you want to go crazy:

```bash
docker compose up -d --scale cache=10
```

```text
[+] Running 1/10
 ✔ Container redis_client_app-cache-1   Running
 ⠼ Container redis_client_app-cache-10  Started
 ⠼ Container redis_client_app-cache-2   Started
 ⠼ Container redis_client_app-cache-4   Started
 ⠼ Container redis_client_app-cache-3   Started
 ⠼ Container redis_client_app-cache-6   Started
 ⠼ Container redis_client_app-cache-8   Started
 ⠼ Container redis_client_app-cache-9   Started
 ⠼ Container redis_client_app-cache-7   Started
 ⠼ Container redis_client_app-cache-5   Started
```

Why is this useful? Well, if you have a lot of jobs to do, you can spin up a lot of workers to do them. If you have a lot of traffic, you can spin up a lot of web servers to handle it. If you have a lot of data, you can spin up a lot of databases to store it. 

#### docker compose logs

Using the logs command of docker compose, we can see the logs of all the containers in the docker compose file.

```bash
docker compose logs
```

```text
cache-1   | 1:M 15 May 2026 00:24:35.211 * oO0OoO0OoO0Oo Valkey is starting oO0OoO0OoO0Oo
cache-1   | 1:M 15 May 2026 00:24:35.211 * Valkey version=8.1.7, bits=64, commit=00000000, modified=0, pid=1, just started
cache-2   | 1:M 15 May 2026 00:24:53.911 * oO0OoO0OoO0Oo Valkey is starting oO0OoO0OoO0Oo
cache-1   | 1:M 15 May 2026 00:24:35.211 # Warning: no config file specified, using the default config. In order to specify a config file use valkey-server /path/to/valkey.conf
cache-3   | 1:M 15 May 2026 00:24:53.984 * oO0OoO0OoO0Oo Valkey is starting oO0OoO0OoO0Oo
cache-1   | 1:M 15 May 2026 00:24:35.212 * Server initialized
cache-2   | 1:M 15 May 2026 00:24:53.912 * Server initialized
cache-3   | 1:M 15 May 2026 00:24:53.985 * Server initialized
cache-1   | 1:M 15 May 2026 00:24:35.212 * Ready to accept connections tcp
cache-2   | 1:M 15 May 2026 00:24:53.912 * Ready to accept connections tcp
cache-3   | 1:M 15 May 2026 00:24:53.985 * Ready to accept connections tcp
```

Just view the logs for a single service:

```bash
docker compose logs cache
```

```text
...
cache-1  | 1:M 15 May 2026 00:24:35.213 * DB saved on disk
cache-2  | 1:M 15 May 2026 00:24:53.912 * oO0OoO0OoO0Oo Valkey is starting oO0OoO0OoO0Oo
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
redis_client_app-app-1
UID    PID     PPID    C    STIME   TTY   TIME       CMD
root   80731   80713   0    22:59   ?     00:00:00   /bin/sh

redis_client_app-cache-1
UID   PID     PPID    C    STIME   TTY   TIME       CMD
999   79610   79578   0    22:57   ?     00:00:01   valkey-server *:6379

redis_client_app-cache-2
UID   PID     PPID    C    STIME   TTY   TIME       CMD
999   85169   85150   0    23:08   ?     00:00:00   valkey-server *:6379

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
docker compose exec app python cache_client.py check_cache
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
 => => naming to docker.io/library/redis_client_app-app
```

If we put this image name in our `.devcontainer/devcontainer.json` file, we are able to use this image as a development environment.

Now in VSCode, in the bottom left, we should see a green button that looks like two arrows. Click on this button and find `Reopen in Containers...` in the dropdown and select it. A new window will pop-up to provide an isolated development environment.

### Run our Python code inside the container
1. Click on the `Run and Debug` section in VSCode
2. Click on the `Run` button and you should see output similar to:
```bash
root@a368d1296c1e:/workspaces/2026-Docker-Bootcamp#  cd /workspaces/2026-Docker-Bootcamp ; /usr/bin/env /usr/local/bin/python /root/.vscode-server/extensions/ms-python.python-2022.8.1/pythonFiles/lib/python/debugpy/launcher 46805 -- redis_client_app/cache_client.py hello_world
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