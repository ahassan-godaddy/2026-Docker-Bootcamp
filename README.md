# 2026 Docker Workshop

## Introduction to Docker

### What is Docker?

_![That's a big question](https://31.media.tumblr.com/a4a72524f0bc49663881898367b5246a/tumblr_ns8pm9eEwN1tq4of6o1_540.gif)_

In their own words:

> Developing apps today requires so much more than writing code. Multiple languages, frameworks, architectures, and discontinuous interfaces between tools for each lifecycle stage creates enormous complexity. Docker simplifies and accelerates your workflow, while giving developers the freedom to innovate with their choice of tools, application stacks, and deployment environments for each project.

Essentially, 

- Docker is a tool that allows you to package code into a Docker image (a re-usable file used to execute code in a Docker container).
- Docker images are the blueprint for Docker containers, which are isolated execution environments.

> If those two terms — "image" and "container" — feel a little squishy, here's an analogy that helps: an image is to a container what a class is to an object, or what a recipe is to a meal. The image is the static, reusable definition. The container is a live, running instance of that definition. You build an image once, then run it as many containers as you want.

> If you've heard of virtual machines (VMs) before, you might be wondering how containers are different. The short version: a VM boots a whole guest operating system on top of your host (full kernel, full init system, full everything), which is heavy and slow. A container shares the host's kernel and only ships your app and its dependencies, which is way lighter and faster to start.

### Why use Docker?

- Docker is a standard package that works across multiple architectures and environment type. i.e. Build a single Docker image that would run the same on Windows vs Mac. 
- Integrate with popular [open-source solutions](https://hub.docker.com/search?q=&type=image) for databases, caching, monitoring, gaming, and more.
- Containers are isolated by default, which shrinks the blast radius of a compromise. For example, if a web application running inside a container is exploited, the attacker lands inside the container's filesystem and namespaces — not the host. This isn't bulletproof (container escapes exist, and misconfiguration like running as root or mounting the Docker socket weakens the boundary), but it's a meaningful layer of defense compared to running services directly on the host.
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

(That command switches you to the `root` user — the all-powerful admin account on Linux. Docker on WSL needs to run as root, which is why we're switching.)

Then type:

```shell
docker
```

This should print the Docker help menu.

> Quick aside on what's actually running: when you install Docker Desktop, it spins up a background process called the **Docker daemon** (sometimes you'll see it called `dockerd`). Every `docker ...` command you type is just a tiny CLI that talks to that daemon over a socket — the daemon is the thing that actually downloads images, starts containers, and manages networks. If you ever stop Docker Desktop, every `docker` command will fail with "Cannot connect to the Docker daemon." That's why.

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

> One thing that confuses a lot of people their first time looking at a Dockerfile: there are two completely different "phases" mixed in here. `FROM`, `WORKDIR`, `COPY`, and `RUN` all happen at **build time** (when you run `docker build`) — they're the steps that produce the image. `CMD` (and its cousin `ENTRYPOINT`, which we'll see later) is what runs at **run time** (when you `docker run` the resulting image). So when you see `RUN pip install ...` in a Dockerfile, that's installing dependencies _into the image_ as it's being built, not every time the container starts.

> Each of those build-time instructions also creates a new **layer** — kind of like a stack of transparency sheets where each one only contains the changes from that step. The final image is all the layers stacked together. We'll come back to layers when we build our own image and watch the cache work.

## Deploying an Open Source image

Each image is different in terms of how you configure the specifics for the application running inside. What's common though, is _how_ you configure the containers. Most images are configured using environment variables and/or by mounting a local Docker volume with configuration files present. 

Let's look at Valkey, as it's a very popular and useful key-value store and caching solution.

### What is Valkey?

Valkey is an in-memory key-value data store that you can use as a database, a cache, a streaming engine, or a message broker. It's a Linux Foundation fork of Redis that started in 2024 (after Redis Inc. switched to a non-OSI license). Valkey stays BSD-licensed and is a drop-in replacement, so the same wire protocol, the same `valkey-cli`, and the same Python client all work.

On my team, we make use of a [library](https://python-rq.org) called `RQ-Python` that builds a queuing system for Python jobs on top of Valkey. We create thousands of jobs each night and have hundreds of worker containers that perform the jobs.

Ok, let's get started.

### Pull the Valkey image

All we need to do is type `docker pull REPOSITORY[:TAG]`. What does this syntax mean? Well docker images are stored in repositories, just like code is stored in git repositories. By default, all images are pulled from [Docker Hub](https://hub.docker.com) - that's a public registry where companies and individuals share their images, kind of like GitHub but for container images. You can also stand up private registries (and big companies usually do), but we won't go over that. The image repository is required, but the tag isn't and will be defaulted to `latest` if nothing is given for it.

```bash
docker pull valkey/valkey:8-alpine
```

Which should output something like: 
```
8-alpine: Pulling from valkey/valkey
Digest: sha256:7e2c6181ad5c425443b56c7c73a9cd6df24a122345847d1ea9bb86a5afc76325
Status: Image is up to date for valkey/valkey:8-alpine
docker.io/valkey/valkey:8-alpine
```

What is happening here? You are pulling the Valkey image from Docker Hub.

> If you ever need really reproducible builds (like in CI), it's a good idea to pin by digest instead of tag. You can grab the digest with `docker buildx imagetools inspect valkey/valkey:8-alpine` and then reference it as `valkey/valkey@sha256:<digest>`.

If you click on one of the tags in that repo, you can see the Dockerfile that backs the image. Here's an example of what an opensource image looks like: https://github.com/valkey-io/valkey-container/blob/mainline/debian/Dockerfile

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

### Expose the cache to your host

> Quick networking primer if you haven't done much of this before. A **port** is just a number that identifies a specific service on a machine — Valkey defaults to 6379 the way HTTP defaults to 80 and SSH defaults to 22. Multiple services can run on the same machine because they each pick a different port. When we say a container is "listening on port 6379", we mean a process inside it is waiting for connections on that number.

So our cache is running, but we can't actually connect to it from our laptop. The container is listening on port 6379, but only inside Docker's internal network (Docker creates this private network automatically when the daemon starts). To talk to it from our host, we need to publish the port using `-p`. Let's stop our existing container and try again:

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

The `-p HOST_IP:HOST_PORT:CONTAINER_PORT` syntax tells Docker to forward traffic from `127.0.0.1:6379` on our host into the container's port 6379. The `127.0.0.1` (also called "loopback" or `localhost`) means "this machine only" — it's an address that always points back at the local computer and isn't reachable from anywhere else. Picking it makes our cache reachable from our own machine but not from anyone else on the network.

Yay! Now our host can talk to Valkey on `localhost:6379`. We can prove it by running another disposable container that connects through the host's network:

```bash
docker run --rm valkey/valkey:8-alpine valkey-cli -h host.docker.internal ping
```

> `host.docker.internal` is a special hostname that Docker invents inside containers — it always resolves back to your host machine. Containers can use it to talk to services running on your laptop without having to know the laptop's actual IP address (which changes when you switch wifi networks).

```
PONG
```

> If you skip the IP and just write `-p 6379:6379`, Docker binds to `0.0.0.0`, which means "all the network interfaces this machine has" — wifi, ethernet, anything else. That's what you want when another machine on your LAN actually needs to connect, but it's easy to forget about and leak on coffeeshop wifi. I'd recommend defaulting to loopback and only broadening when you need to.

### View container in container list

> Check the status of the container

```bash
docker ps
```

This should output something like: 
```
CONTAINER ID   IMAGE                    COMMAND                  CREATED          STATUS          PORTS                      NAMES
16ad2cca6925   valkey/valkey:8-alpine   "docker-entrypoint.s…"   22 seconds ago   Up 21 seconds   127.0.0.1:6379->6379/tcp   cache
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

Valkey is a key-value cache, so it allows for very quick reads and writes. Let's store some data.

Read the following command like: 
> docker Execute interactive (-i) with a real shell (-t) cache (container name) valkey-cli (command to run inside container) SET myname Andrew (arguments for the command ie. valkey-cli)

> If `docker exec` feels confusing: think of it like SSH-ing into a remote machine. The container is already running and minding its business; `exec` just starts a new process inside it that shares its filesystem and network. The `-it` flag pair (`-i` interactive, `-t` allocate a TTY) is what makes it feel like a real interactive terminal session.

```bash
docker exec -it cache valkey-cli SET myname Andrew
```

Here we are using `valkey-cli` (the CLI tool that Valkey ships) to interact with the cache inside a container named `cache`. Which should output: 
```
OK
```

This is the response from the cache, telling us that the data was stored successfully.

### Get data from the cache

Retrieving the data we put into the cache is just as easy as storing it. 

```bash
docker exec -it cache valkey-cli GET myname
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
docker exec -it cache valkey-cli GET myname
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
docker exec -it cache valkey-cli GET myname
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
docker run --rm --name cache -d valkey/valkey:8-alpine && docker exec -it cache valkey-cli GET myname; docker stop cache;
```

Which should output: 
``` 
<the new container id>
(nil) <------- this is us trying to get the data again, and it no longer exists

cache
```

## Telling Docker how to behave

So far we've been trusting Docker's defaults for everything, which is fine on a laptop. But what happens if our container goes nuts and tries to eat all our memory? Or what if it crashes and we want it to come back automatically? Let's look at a couple of `docker run` flags that come in handy for these situations.

### Capping memory and CPU

Without limits, a container can use every byte of RAM and every CPU cycle on the host. That's how one misbehaving service takes down everything else running on the same box. Let's tell Docker to cap our cache at 64 MiB and half a CPU:

```bash
docker rm -f cache
docker run --name cache --memory 64m --cpus 0.5 -d valkey/valkey:8-alpine
docker stats --no-stream cache
```

```
CONTAINER ID   NAME      CPU %     MEM USAGE / LIMIT   MEM %     NET I/O         BLOCK I/O   PIDS
61f1e97c6d75   cache     0.35%     12.72MiB / 64MiB    19.88%    1.17kB / 126B   0B / 0B     5
```

There it is in the `MEM USAGE / LIMIT` column - our 64 MiB ceiling. If the container ever tries to allocate past that limit, the Linux OOM killer (out-of-memory killer - a kernel feature that picks a process to terminate when memory runs out) steps in and kills the process inside. Docker's just leaning on the kernel's cgroups (control groups - the Linux feature that lets the OS group processes and enforce resource limits on them) to do all this for us.

### Bringing the container back when it falls over

What if our process crashes? By default, the container just exits and stays dead. We have to manually start it again. The `--restart` flag tells Docker to bring it back for us:

```bash
docker rm -f cache
docker run --name cache --restart unless-stopped -d valkey/valkey:8-alpine

# Simulate a crash by telling Valkey to shut itself down ungracefully
docker exec cache valkey-cli SHUTDOWN NOSAVE || true
sleep 3
docker ps --filter name=cache --format "table {{.Names}}\t{{.Status}}"
docker inspect cache --format 'RestartCount={{.RestartCount}}'
```

```
NAMES     STATUS
cache     Up 2 seconds
RestartCount=1
```

The container died and Docker brought it back! `RestartCount=1` is the proof. There are four restart policies you can use:

- `no` - never restart (this is the default).
- `on-failure[:N]` - only restart if the process exits with a non-zero code, optionally up to N times.
- `always` - restart no matter what, including when the Docker daemon itself restarts.
- `unless-stopped` - like `always`, but if you ran `docker stop cache` yourself, it stays stopped. This is usually the one you want.

> Note: `docker stop` signals intentional shutdown — `unless-stopped` honours that and won't restart the container. But `docker kill` sends SIGKILL, which looks like a crash, so the restart policy _will_ kick in. That's why we simulate a crash from inside the container with `SHUTDOWN NOSAVE` instead.

We'll see one more useful runtime flag - `-e` for setting environment variables - in a bit, after we've built our own image.

Let's clean up before moving on:

```bash
docker rm -f cache
```

## Using [Docker Volumes](https://docs.docker.com/storage/volumes/) to preserve container data

In modern container orchestration technologies such as Kubernetes or Docker-Swarm (those are tools that schedule and manage containers across many machines — we won't go into them in this workshop, but it's good to know they exist), it's extremely common for containers to be removed and replaced with a different container. These two containers will have different ids, but they run the same application. As we just saw, when a container is removed it's data is also removed... so how can we make sure that the cache data isn't deleted when the container is deleted? This matters a lot for **stateful** applications — things like databases or caches that are supposed to remember data between restarts. (Stateless apps, like a static web server, don't have this problem because they forget everything on every start anyway.)

> Docker Volumes give you a chunk of persistent storage that lives outside the container's lifecycle. Docker manages where the data actually sits on disk for you (on Mac/Windows it ends up inside the Docker Desktop VM; on Linux it's in `/var/lib/docker/volumes`). There's a related concept called a **bind mount** where you point at a specific directory on your host instead — we'll see those used in Part 2 for things like mounting source code into a dev container.

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
docker exec -it cache valkey-cli
```

Which will take you into the valkey-cli shell. Run these commands:

```
127.0.0.1:6379> SET myname Andrew
OK
127.0.0.1:6379> SET moredata potato
OK
127.0.0.1:6379> exit
```

Then exit the container. Validate that our new data is present by running:

```bash
docker exec -it cache valkey-cli GET moredata
```

Which should output:

```text
"potato"
```

Now let's go back into the container and run these commands manually.

```bash
docker exec -it cache valkey-cli
```

Which will take you back into the valkey-cli shell. Run these commands to validate that the data still exists:

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
docker exec -it cache valkey-cli GET myname
```

```
"Andrew"
```

This is one of the most fundamental concepts of Docker. By using volumes, you can ensure that your data is preserved even when the container is removed. This is extremely useful for databases, caches, and other stateful applications.

## Create custom Docker images

Let's create a container to utilize the code in `cache_client_app/cache_client.py`. Our image is going to look very similar to the one we viewed earlier. With [Dockerfiles](/cache_client_app/Dockerfile), it's extremely important to put the things that change _least_ at the top, as Docker will build and cache the `layers` it generates from this file. This is so that on subsequent builds, you won't need to wait for the entire command again (unless you explicitly want to run it without cache, which is possible). 

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

> A quick note on `ENTRYPOINT` vs `CMD`: you saw `CMD` in the first Dockerfile we looked at; here we're using `ENTRYPOINT`. Both define what runs when the container starts — the difference is that `ENTRYPOINT` is the executable that always runs, and any extra arguments you pass to `docker run` become _arguments_ to it. So `docker run bootcamp check_cache` runs `python3 cache_client.py check_cache`. With `CMD`, those extra arguments would replace the whole command instead of being appended to it. `ENTRYPOINT` is what you want when your image is essentially "a wrapped binary."

> Question to think about: Why would we copy over the requirements file first, before copying over the rest of the app?

### Build our image

Build our container and tag (name) it as "bootcamp". The trailing `cache_client_app` tells docker what **build context** to use — that's the directory Docker packages up and ships to the daemon to build from. In this case we want to be inside the folder that has our code. Hold on to that "build context" term, you'll see it again soon.

```bash
docker build -f cache_client_app/Dockerfile -t bootcamp cache_client_app
```

### Build it again, and watch the layer cache work

Now run the exact same `docker build` command a second time:

```bash
docker build -f cache_client_app/Dockerfile -t bootcamp cache_client_app
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

Wait, what just happened? It finished in under a second and every step says `CACHED`! Docker is fingerprinting the inputs to each Dockerfile instruction and reusing the layer it already built if nothing changed. Pretty cool, right?

Now let's edit a source file and rebuild:

```bash
# pretend you fixed a typo in cache_client.py
echo '# tweak' >> cache_client_app/cache_client.py
docker build -f cache_client_app/Dockerfile -t bootcamp cache_client_app
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

The expensive dependency layers are still `CACHED`, but `COPY . .` and everything below it re-ran. This is why we copy `requirements.txt` and install our dependencies _before_ we `COPY . .`. If we did it the other way around, every code change would invalidate the dependency layer and Docker would reinstall everything from scratch.

To prove that, let's actually bust the dependency cache by touching `requirements.txt`:

```bash
echo "" >> cache_client_app/requirements.txt
docker build -f cache_client_app/Dockerfile -t bootcamp cache_client_app
```

```
#10 [stage-1 3/7] COPY requirements.txt requirements.txt
#10 DONE 0.0s
#11 [builder 3/4] COPY requirements.txt requirements.txt
#11 DONE 0.0s
#12 [builder 4/4] RUN pip install --upgrade pip && pip wheel --wheel-dir /wheels -r requirements.txt
#12 0.834 Collecting valkey==6.1.1 ...
#12 DONE 6.1s
```

And there it is - the wheel build runs from scratch and we're back to multi-second builds. So the order of instructions in your Dockerfile really matters. Put the things that change least at the top, and the things that change most at the bottom.

> If you ever suspect that a cached layer is masking a bug, you can force a clean rebuild with `docker build --no-cache ...`. It's slow, so only reach for it when you really need to.

Before moving on, let's revert the demo edits so our working tree is clean again:

```bash
# Drop the trailing comment we appended and the blank line in requirements.txt
sed -i.bak -e '${/^# tweak$/d;}' cache_client_app/cache_client.py && rm cache_client_app/cache_client.py.bak
sed -i.bak -e '${/^$/d;}' cache_client_app/requirements.txt && rm cache_client_app/requirements.txt.bak
```

### Use a `.dockerignore` to send less to the build daemon

When we run `docker build`, the first thing Docker does is package up the entire directory we pointed at - this is called the _build context_ - and send it over to the build engine. Let's see how big our context actually is:

```bash
du -sh cache_client_app
```

```
20K	cache_client_app
```

20 KB is no big deal. But imagine if we had a `.git` folder in there, or a `.venv` with hundreds of MB of installed packages, or some local test data. All of it would be packaged up and sent on every single build, even if our Dockerfile never actually `COPY`s it. Worse, if we ever wrote `COPY . .`, files like `.env` with secrets could end up baked into our image. Yikes.

The fix is a file called `.dockerignore` that lives next to our Dockerfile. It uses the same syntax as `.gitignore`:

```bash
cat cache_client_app/.dockerignore
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

Anything that matches these patterns gets skipped when Docker builds the context. Treat `.dockerignore` as a habit you always have - you almost never want your `.git` folder, your virtualenvs, or any local credentials sitting inside your build context.

### Why does our Dockerfile have two `FROM` lines?

If you look back at the Dockerfile from earlier, you might have noticed that there are _two_ `FROM python:3.13-slim-trixie` lines. The first one is named `AS builder`, and the second is the actual final image. This is called a **multi-stage build**, and it's a really powerful pattern for keeping your images small.

Here's what's happening: the `builder` stage installs `pip`, downloads our dependencies, and compiles them into wheel files. That stage produces a `/wheels` directory. Then the final stage starts fresh from the same slim base and only copies the `/wheels` directory over with `COPY --from=builder`. All the toolchain stuff that pip needed - caches, compiled C bindings' source files, intermediate downloads - stays trapped inside the builder stage and gets discarded. Only the final stage becomes our image.

Let's compare image sizes to see the impact:

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

Our app image is only about 20 MB heavier than the bare Python base. Without multi-stage builds, a naive `FROM python:3.13` + `RUN pip install` setup would easily land at 1+ GB because the full Python image plus all of pip's caches and toolchain would stick around. Multi-stage is how we ship lean images without having to rewrite our app in Go.

> If you want to take this even further, you can swap the final stage for a distroless image (these are base images with literally no shell, no package manager, no extra utilities — just Python and your code) to shrink the attack surface (the parts of your system an attacker could try to exploit; smaller is better) even more. Something like:
> ```Docker
> FROM gcr.io/distroless/python3-debian12
> WORKDIR /app
> COPY --from=builder /wheels /wheels
> COPY . .
> ENTRYPOINT ["python3", "cache_client.py"]
> ```

> Also, if you're on Apple Silicon and you want your image to also work on regular x86 servers, you can use BuildKit to build for multiple architectures at once: `docker buildx build --platform linux/amd64,linux/arm64 -t bootcamp:2026 cache_client_app`.

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
  File "/usr/local/lib/python3.13/site-packages/valkey/connection.py", line 1192, in get_connection
    connection.connect()
  File "/usr/local/lib/python3.13/site-packages/valkey/connection.py", line 563, in connect
    raise ConnectionError(self._error_message(e))
valkey.exceptions.ConnectionError: Error -2 connecting to cache:6379. Name or service not known.
```

> Doh! What's going on? Well remember how everything is isolated, this is actually a good thing. You need to explicitly tell docker that these containers can communicate with eachother. To do this, we need to create a Docker Network.

#### Quick sidebar - the `-e` flag we mentioned earlier

> If you've never run into them before: an **environment variable** is just a key/value pair (like `DATABASE_URL=postgres://...` or `LOG_LEVEL=debug`) that any process running on the system can read. Programs check them at startup to find things like database hostnames, API keys, and feature flags - they're a clean way to configure software without having to recompile or edit code. Every operating system has them, and they're inherited by child processes. Docker containers get their own isolated set, and `-e` lets us pre-populate them.

Before we wire up the network, take another look at the error message above. It says `connecting to cache:6379`. Where did `cache` come from? It's the default in our Python code: `os.environ.get("CACHE_HOST", "cache")`. We don't want to bake configuration like hostnames into our image - we want to be able to inject it at runtime. That's exactly what the `-e` flag is for:

```bash
docker run --rm -e CACHE_HOST=somehost.invalid bootcamp check_cache 2>&1 | tail -3
```

```
  File "/usr/local/lib/python3.13/site-packages/valkey/connection.py", line 397, in connect_check_health
    raise ConnectionError(self._error_message(e))
valkey.exceptions.ConnectionError: Error -2 connecting to somehost.invalid:6379. Name or service not known.
```

Now the error references `somehost.invalid` instead of `cache`! Our injected value won. This is how one image can work in dev, staging, and prod - the env vars change, but the image stays the same. You can pass `-e` multiple times for multiple variables, or use `--env-file path/to/.env` to load a whole file at once.

### Connect Docker Containers

#### docker network create
Create a docker network to act as an network environment for multiple containers.

```bash
docker network create bootcamp_net
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

The `docker-compose.yml` file has its own syntax, syntax versions, and a [ton of useful tools](https://docs.docker.com/compose/compose-file/compose-file-v3/) that we won't have time to go over here.

> If you haven't seen YAML before, it's an indentation-based config format - kind of like JSON but designed to be more human-friendly. Indentation is meaningful (so be careful with tabs vs spaces - YAML wants spaces), `key: value` defines a property, and items prefixed with `-` are list entries. That's basically all you need to know to read this.

Here's what [a docker-compose.yml file](/cache_client_app/docker-compose.yml) looks like: 

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

Did you notice the `${CACHE_HOST:-cache}` in the `environment:` block above? That's compose's variable substitution syntax: it reads the value from a variable named `CACHE_HOST`, or falls back to the literal string `cache` if it's not set. You'll see this pattern all over the place in real-world compose files - it's how teams keep one compose file working across dev, CI, and production.

Compose actually looks in a few different places for the value of a variable. In order of priority:

1. The shell environment - `CACHE_HOST=somehost docker compose up` will override anything else.
2. A `--env-file path/to/file` passed explicitly on the command line.
3. A `.env` file sitting in the same directory as `docker-compose.yml` - this gets auto-loaded.

If you're not sure what compose will end up using, you can run `docker compose config` to preview it. This expands all the variables and prints the fully-resolved YAML:

```bash
cd cache_client_app && docker compose config
```

```yaml
services:
  app:
    environment:
      CACHE_HOST: cache
    ...
```

The default kicked in because we hadn't set `CACHE_HOST` anywhere. Let's override it from the shell:

```bash
CACHE_HOST=somehost.invalid docker compose config | grep -A1 environment
```

```
    environment:
      CACHE_HOST: somehost.invalid
```

Or we can load from a file. Create `/tmp/bootcamp.env` with `CACHE_HOST=valkey` inside, then:

```bash
docker compose --env-file /tmp/bootcamp.env config | grep -A1 environment
```

```
    environment:
      CACHE_HOST: valkey
```

> Quick note: `.env` is great for non-secret config like hostnames, ports, and log levels. For actual secrets like passwords and API keys, you should use Docker secrets instead. We'll see that pattern in Part 2.

### docker compose cli

#### docker compose up
The following command will create the network, the volume, both containers (in the background), and the proper links:

```bash
cd cache_client_app && docker compose up -d --build
```

For live development in Compose v2.22+, run watch mode in a separate terminal:

```bash
docker compose watch
```

```
...
 Container cache_client_app-cache-1  Started
 Container cache_client_app-app-1    Started
```

#### docker compose ps
Let's check on it! Run the following command to see the status of everything:

```bash
docker compose ps
```

```
NAME                         IMAGE                    COMMAND                  SERVICE   STATUS                   PORTS
cache_client_app-app-1       cache_client_app-app     "/bin/sh"                app       Up 8 seconds (healthy)
cache_client_app-cache-1     valkey/valkey:8-alpine   "docker-entrypoint.s…"   cache     Up 8 seconds            6379/tcp
```

> The `Healthy` status above indicates that the command we defined as the healthcheck is returning without failing. Docker runs that command on whatever interval you set (every 3 seconds in our compose file) and watches the exit code: zero means healthy, non-zero means unhealthy. Healthchecks are how other services can wait for this one to actually be ready before they start using it.

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
 ✔ Container cache_client_app-cache-1  Running
 ⠹ Container cache_client_app-cache-2  Started
```

or if you want to go crazy:

```bash
docker compose up -d --scale cache=10
```

```text
[+] Running 1/10
 ✔ Container cache_client_app-cache-1   Running
 ⠼ Container cache_client_app-cache-10  Started
 ⠼ Container cache_client_app-cache-2   Started
 ⠼ Container cache_client_app-cache-4   Started
 ⠼ Container cache_client_app-cache-3   Started
 ⠼ Container cache_client_app-cache-6   Started
 ⠼ Container cache_client_app-cache-8   Started
 ⠼ Container cache_client_app-cache-9   Started
 ⠼ Container cache_client_app-cache-7   Started
 ⠼ Container cache_client_app-cache-5   Started
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
cache_client_app-app-1
UID    PID     PPID    C    STIME   TTY   TIME       CMD
root   80731   80713   0    22:59   ?     00:00:00   /bin/sh

cache_client_app-cache-1
UID   PID     PPID    C    STIME   TTY   TIME       CMD
999   79610   79578   0    22:57   ?     00:00:01   valkey-server *:6379

cache_client_app-cache-2
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
 => => naming to docker.io/library/cache_client_app-app
```

If we put this image name in our `.devcontainer/devcontainer.json` file, we are able to use this image as a development environment.

Now in VSCode, in the bottom left, we should see a green button that looks like two arrows. Click on this button and find `Reopen in Containers...` in the dropdown and select it. A new window will pop-up to provide an isolated development environment.

### Run our Python code inside the container
1. Click on the `Run and Debug` section in VSCode
2. Click on the `Run` button and you should see output similar to:
```bash
root@a368d1296c1e:/workspaces/2026-Docker-Bootcamp#  cd /workspaces/2026-Docker-Bootcamp ; /usr/bin/env /usr/local/bin/python /root/.vscode-server/extensions/ms-python.python-2022.8.1/pythonFiles/lib/python/debugpy/launcher 46805 -- cache_client_app/cache_client.py hello_world
Oh hai
```
3. If you want to experiement more, add a breakpoint to the hello_world method and it should stop on that line next time you run.

How does this work? VSCode has a `.vscode/launch.json` file that you can add run configurations into. This is extremely powerful and dynamic and will allow you to run most workloads right in VSCode.

## Scanning images with Docker Scout

Before we push our image anywhere, it's worth running a quick vulnerability check on it. Docker has a built-in tool called Scout that does exactly this:

```bash
docker scout quickview bootcamp:2026
docker scout cves bootcamp:2026
docker scout recommendations bootcamp:2026
```

`quickview` gives you a high-level summary, `cves` lists every known CVE (CVE = "Common Vulnerabilities and Exposures" — a publicly tracked security flaw with an ID like `CVE-2024-12345`) in the image and its dependencies, and `recommendations` suggests things you can change (like newer base images) to clean up the issues. Pretty handy as a last step in your workflow before shipping.

## Running a Local LLM in Docker

One of the coolest things you can do with Docker is spin up a local large language model in a single command. No Python environment to set up, no dependencies to wrestle with — Docker Desktop ships with a built-in inference engine called **Docker Model Runner** (DMR) that handles everything.

### Enable Docker Model Runner

In Docker Desktop, go to **Settings → AI → Enable Docker Model Runner**. That's it — no containers to configure, no extra images to pull. DMR runs as part of the Docker engine itself using llama.cpp under the hood.

Verify it's working:

```bash
docker model version
```

```
Docker Model Runner version v0.1.41
Docker Engine Kind: Docker Desktop
```

### Pull a small model

SmolLM2 is a 362 million parameter model that weighs in at just 270 MB — small enough to run on any laptop without a GPU:

```bash
docker model pull ai/smollm2
```

```
Downloaded 270.60MB of 270.60MB
Model pulled successfully
```

Models are pulled from Docker Hub as OCI artifacts (the same format as container images) and cached locally. You only download them once.

### List your models

```bash
docker model list
```

```
MODEL NAME  PARAMETERS  QUANTIZATION    ARCHITECTURE  MODEL ID      CREATED        SIZE
ai/smollm2  361.82 M    IQ2_XXS/Q4_K_M  llama         354bf30d0aa3  15 months ago  256.35 MiB
```

### Chat with it

You can talk to the model directly from the command line by piping in a prompt:

```bash
echo "What is Docker in one sentence?" | docker model run ai/smollm2
```

```
Docker is a package manager that enables running multiple operating systems
on a single computer in a container, making it a popular choice for
developers and IT professionals.
```

Or ask it to explain something simply:

```bash
echo "Explain containers to a 5 year old in 2 sentences" | docker model run ai/smollm2
```

```
Imagine you have many toys in your house, and you want to pack them up to
take them somewhere. Containers can help you do that! They are special boxes
that you can put your toys inside to keep everything safe and organized.
```

Running `docker model run ai/smollm2` without a pipe drops you into an interactive chat session — type your messages and hit Enter, then Ctrl-D or Ctrl-C to exit.

### Use the REST API

DMR also exposes an OpenAI-compatible API. From inside a container, hit `http://model-runner.docker.internal`:

```python
import requests

response = requests.post("http://model-runner.docker.internal/engines/v1/chat/completions", json={
    "model": "ai/smollm2",
    "messages": [{"role": "user", "content": "What is a Docker volume?"}],
})
print(response.json()["choices"][0]["message"]["content"])
```

This means any container in your compose stack can call the model without network config or extra services — DMR is just part of Docker.

### Why this matters

The pattern here is exactly what we've been doing all workshop — pull something from a registry, run it, talk to it. The fact that it happens to be running a language model is incidental. You could add an `/ask` endpoint to your Django app from Part 2 that proxies to DMR, and you'd have an AI-powered web app running entirely on your laptop with zero cloud dependencies.

### Clean up

```bash
docker model rm ai/smollm2
```

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