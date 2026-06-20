# Installation

The build script is intended to be able to work on different types of Linux distributions.
Currently it is written mainly for Debian, but infrastructure is there to extend to other
distributions.

# How builds run

Builds always run inside Docker containers. The host system no longer executes
recipes directly: it only orchestrates `docker run`. This means the host does not
need build tools (gawk, fakeroot, subversion, etc.) installed, and no `sudo apt-get`
is run on the host for installing or removing build dependencies — those happen
inside the container, which is ephemeral.

The native build path is retained only for in-container use by the `-S` dev shell,
where there is no Docker-in-Docker available.

# Dependencies

## Host

The only host requirement is a working Docker installation:

```
apt install docker.io
```

(or your distribution's equivalent), and ensure the build user is in the `docker`
group (or can otherwise access the Docker daemon).

## Docker images

The build script uses custom Debian-based images that contain the build tools
and an entrypoint. Build them from the Dockerfiles in the `docker/` directory,
e.g. for Debian bookworm:

```
docker build -t build-bookworm:latest -f docker/Dockerfile.bookworm docker
```

Repeat for any other distribution you want to build for (trixie, etc.).

# Configuration example

It is best to use a non-root user for running build (we will use user builduser in the example
below).

In order to set things up, follow the steps below.

* Become the builduser

```su - builduser```
* Create a local binary directory for the user and add it to the path

```
mkdir bin
echo 'export PATH=$PATH:~/bin' >> .bashrc
```
* Check out the repository

```
cd bin
git clone https://github.com/mverboom/build.git build.git
```
* Setup some symlinks

```
ln -s build.git/build build
ln -s build.git/debclean debclean
ln -s build.git/torepo torepo
```
* Copy the example configuration files

```
cp build.git/buildrc-example ~/.buildrc
cp build.git/toreporc-example ~/.toreporc
```
* Modify any settings you want changed in the example configuration files.
  In particular, set `BUILDDISTRO` to the target distribution (required on the
  host, e.g. `bookworm`).

# Example build

You should now be ready to build your first recipe. Assuming you have stayed with the default
file locations, do the following.

* Create the recipe directory

```
mkdir ~/recipes
```
* Copy the build example recipe over

```
cp ~/bin/build.git/example-recipes/build.recipe ~/recipes
```
* Build the build recipe and create a package (specify the target distro with `-d`)

```
build -b -p -d bookworm build
```
* You should now have a packge in the packages directory.