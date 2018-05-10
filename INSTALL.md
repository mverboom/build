# Installation
In order to use this script you need to setup the following:

* Debian system with the following packages
```
apt install gawk subversion fakeroot hgsubversion grep wget bzip2
```
* Optionally, you can also (already) install the following
```
apt install build-essential cmake
```
* [Best practice] Create a seperate useraccount to run the builds with
```
adduser builduser
```
* Retrieve the latest version of the script available from the Github
```
su - builduser
mkdir ~/git
cd ~/git
git clone https://github.com/mverboom/build.git
mkdir ~/bin
ln -s build ~/bin
ln -s debclean ~/bin
ln -s torepo ~/bin
```
* Configure your environment
```
cp ~/git/build/buildrc-example ~/.buildrc
vi ~/.buildrc
```
* Create the directory where your recipes are in (adjust according to what you configured in buildrc)
```
mkdir ~/recipes
```
