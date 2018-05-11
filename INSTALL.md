# Installation

The build script is intended to be able to work on different types of Linux distributions.
Currently it is written mainly for Debian, but infrastructure is there to extend to other
distributions.

Required dependancies will vary with the distribution being used.

# Dependancies

## Debian

On a debian system, the following packages are required:

```
apt install gawk subversion fakeroot hgsubversion grep wget bzip2
```

It is usually best to keep the base installation of the system as clean as possible in order
to make sure the recipes have the correct packages in them that are really required to build
the recipe.

# Configuration example

It is best to use a non-root user for running build (we will use user builduser in the example
below).

In order to be able to automatically install and remove packages required for running the
recipes, give the build user sudo rights as root to run the relevant package commands.

* Debian: apt-get

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
* Build the build recipe and create a package
```
build -b -p build
```
* You should now have a packge in the packages directory.
