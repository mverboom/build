# Multi

Initially build has been made to easily create debian packages. However,
it would be very handy to also make other types of packages. The most important
being rpm packages.

Some infrastructure is in place to build packages for different platforms, but
this is not complete.

This file documents the issue's that need to be fixed.

## Global assumptions

It seems useful to implement builds for different package envirements into
1 recipe and not create multiple recipes for the same type of software.

This assumes that it is possible to run the same set of build commands and
not depend on the system it is run on.

#### Progress

* [ ] Check assumption

## Build environment requirements

The script needs to check for required software based on the type of os it
is running on.

#### Progress

* [x] Add OS detection
* [x] Create OS dependant required software function
* [ ] Push changes upstream

## Created binary storage

The script splits the generated output from the build phase based on arch.
Normally the folling are used:

* all
* i386
* amd64

This does not take into account on which type of system the output is generated.

The issue might be that an rpm based system might generate different binaries
and links to different libraries than a deb based system.

If this is the case, the build directory structure should be changed to reflect
this.

#### Progress

* [ ] Determine if this is an issue

## Per OS required package for build

When running the building phase of a recipe, certain software is required
to run the build phase. This currently is a generic list of software and is
targeted towards debian based systems. This needs to be changed so there is
a platform specific set of required packages for the build phase.

#### Progress

* [ ] Determine new syntax for required packages
* [ ] Update documentation to reflect syntax that should be used
* [ ] Extend script to provide backwards compatability defaulting to debian
* [ ] Add support for installing required software on rpm based system
* [ ] Push changes upstream

## RPM package build

Currently there is only a debian package build function available. This
needs to be extended to rpm support, including the relevant specification
in the recipe file.

#### Progress

* [ ] Extend function to split into a deb and rpm branch
* [ ] Determine required section in recipe to build a rpm
* [ ] Document recipe section for rpm
* [ ] Implement rpm building
* [ ] Push changes upstream

## Debclean script

The debclean script was named debclean and specifically for debian. However,
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

# [ ] Add rpm option to recipe
# [ ] Test rpm building
# [ ] Update documentation
# [ ] Push changes upstream

## Pushing package to repo

The current example script to push a package to a repo has no infrastructure
to change the actions depending on the package type.

#### Progress

* [ ] Add support for different repo pushes depending on package type
* [ ] Update documentation
* [ ] Push changes upstream
