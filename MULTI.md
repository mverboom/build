# Multi

Initially build has been made to easily create Debian packages. However,
it would be very handy to also make other types of packages. The most important
being rpm packages.

Some infrastructure is in place to build packages for different platforms, but
this is not complete.

This file documents the issue's that need to be fixed.

## Global assumptions

It seems useful to implement builds for different package environments into
1 recipe and not create multiple recipes for the same type of software.

This assumes that it is possible to run the same set of build commands and
not depend on the system it is run on.

#### Progress

* [x] Check assumption

## Build environment requirements

The script needs to check for required software based on the type of os it
is running on.

#### Progress

* [x] Add OS detection
* [x] Create OS dependant required software function
* [x] Push changes upstream

## Created binary storage

The script splits the generated output from the build phase based on arch.
Normally the following are used:

* all
* i386
* amd64

This does not take into account on which type of system the output is generated.

The issue might be that an rpm based system might generate different binaries
and links to different libraries than a deb based system.

If this is the case, the build directory structure should be changed to reflect
this.

The best solution up till now seems to be the following.

In order to keep backwards compatibility, the more detailed information on
which system was used to generate the binaries is a recipe level selection.

Default behaviour is:
 $DESTDIR/arch/<recipename>

A configuration option can be introduced to the [INFO] section of a recipe
that can modify this behaviour. For example:

 dest=dist

This would add the OS distribution name to the name of the recipe, so:

 $DESTDIR/arch/<recipename>-redhat

Useful options here would be:

* dist: append distribution name (-redhat)
* dist-major: append distribution name and major version numbers (-redhat-6)
* dist-minor: append distribution name and major and minor version numbers (-redhat-6-5)

The list of conversions to use for each distribution:

* RedHat: rh
* Debian: deb
* Fedora: fed
* Scientific Linux: sci
* Centos: cen

#### Progress

* [x] Determine if this is an issue
* [x] Specify directory layout
* [ ] Determine codes to use for distributions
* [ ] Create current OS to distribution conversion function
* [ ] Make OS information available through environment during BUILD phase
* [ ] Add configuration item to info section
* [ ] Update all references to DESTDIR to comply to configuration item
* [ ] Check build platform vs. configuration item when building
* [ ] Check build platform vs. configuration item when packaging
* [ ] Update documentation

## Per OS required package for build

When running the building phase of a recipe, certain software is required
to run the build phase. This currently is a generic list of software and is
targeted towards Debian based systems. This needs to be changed so there is
a platform specific set of required packages for the build phase.

Currently there is one [REQUIRED] section in a recipe. To provide good backwards
compatibility it is probably best to create the following behaviour:

* Only a line with required packages in the section: use for all OS environments
* Prefix with line with OS tag and optional version: line only to be used for specific os

Examples for the specific OS lines would be as follows:

RedHat, non specific os release:

rh=rpm-python,perl-IO-Zlib

RedHat version 6

rh-6=xmlrpc-c-1.16.24-1210.1840.el6.x86_64,perl-libxml-perl-0.08-10.el6.noarch

#### Progress

* [x] Determine new syntax for required packages
* [ ] Make infrastructure to select correct line of packages to use
* [ ] Add support for installing required software on rpm based system
* [ ] Update documentation to reflect syntax that should be used
* [ ] Push changes upstream

## RPM package build

Currently there is only a Debian package build function available. This
needs to be extended to rpm support, including the relevant specification
in the recipe file.

#### Progress

* [ ] Extend function to split into a deb and rpm branch
* [ ] Determine required section in recipe to build a rpm
* [ ] Document recipe section for rpm
* [ ] Implement rpm building
* [ ] Push changes upstream

## Debclean script

The debclean script was named debclean and specifically for Debian. However,
the configuration file only has support for 1 post processing command. The
best solution seems to be to change the debclean script to a generic clean
script, that runs the appropriate action depending on the type of packaging
the system uses.

#### Progress

* [x] Initial changeover to clean script
* [ ] Push changes upstream
* [ ] Implement rpm solution
* [ ] Push changes upstream

## Update test recipe

The test recipe should reflect a way to build it on an rpm system

#### Progress

* [ ] Add rpm option to recipe
* [ ] Test rpm building
* [ ] Update documentation
* [ ] Push changes upstream

## Pushing package to repo

The current example script to push a package to a repo has no infrastructure
to change the actions depending on the package type.

#### Progress

* [ ] Add support for different repo pushes depending on package type
* [ ] Update documentation
* [ ] Push changes upstream
