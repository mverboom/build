# NAME

build - automate building of software

# SYNOPSIS

`build [OPTION]... [RECIPE]...`

# DESCRIPTION

Automates the building of software, although it should be considered alpha
quality software at best.

The building process is described by recipe files which are explained in the
recipe section.

Arguments that can be used are divided into two types:

**Operational mode:**

`-c`
Check version, runs the version check section of the specified recipe(s).

`-b`
Build, runs the build version of the specified recipe(s).

`-p`
Package, runs the package secition of the specified recipe(s).

`-r`
To repository, creates packages and copies to repository for specfified recipe(s).

**Operation modifiers:**

`-a`
Process all recipes in the recipe directory.

`-v`
Specify specific version, will prevent from running version section of recipe(s)

`-q`
Quiet output.
Specify once will still show output on succesfull and failed builds.
Specify twice will not show output.

`-x`
Enable debugging output

`-f`
Force build for recipe, even if complete build is already available.

`-i`
Specify an instance for a recipe

`-R`
Do not remove required packages after build and skip any post build script.

`-h`
This help message

# CONFIGURATION FILE

The script uses a configuration file which is located at:

`~/.buildrc`

The file has the following format:

`VARIABLE=value`

The following variable can be set in the configuration file.

`DESTDIR` (defaults to ~/build)
Destination directory where compiled software should be put.

`CACHEDIR` (defaults to ~/cache)
Download cache directory where downloaded files are placed.

`TMPDIR` (defaults to ~/temp)
Temporary directory where the software building takes place.

`RECIPEDIR` (defaults to ~/recipes)
Directory with recipe files.

`PKGLIST` (defaults to RECIPEDIR/pkglist)
File used for package administration.

`PKGDIR` (defaults to ~/packages)
Directory where built packages are placed

`TODEBREPO`
Points to script to use to publish Debian package to repository. This script
can get the -q (quiet) option passed if the build process is run with -q. If
multiple packages are processed, all which be passed to the script in a single
go.

`INSTDEP` (defaults to yes)
If set to yes will try to install the required packages specified in the
recipe for the build. This requires the user running the script to have
sudo rights to install packages.

`DEINSTDEP` (defaults to yes)
if set to yes will try to remove the packages that were required for the
build process. This requires the user running the script to have sudo
rights to remove packages.

`PKGPOSTFIX`
This optional parameter defines an addition to the package name and can help
identify package build by the script in a repository or system.

`POSTBUILD`
This can point to an optional script to be run after the build process is
complete. The included debclean script can for example be used here.

# RECIPE

During building recipes are used for the various steps in the build process.

Recipes are stored in the recipe directory. Optionally that directory can also
contain a folder specific for the recipe. For example, a recipe called `test.recipe`
can also have a folder `test.files`. This directory can contain supporting information
used during the different phases of building and packaging software.

Any lines in a recipe that start with `#` will be ignored and can be used for
comments.

Below the specific recipe sections will be discussed for the different operation
modes.

## GENERIC

A recipe is build up in .ini file style format. Each section has a specific name
and contains the information required for its function. Not every section is
mandatory.

Sections in recipes not related to an operation mode are:

`[INFO]` (optional)

The following options can be set:

excludefromall
If this option is set to 1, the recipe will not be included when running the build
script with the -a flag. This can be useful for recipes under development, not ready
to include in a nightly run.

## CHECK VERSION

For checking of the current version of the software available the following section
is required:

`[VERSION]` (mandatory)

Everything in this section is executed. The expected result is the version of the
software. Before the code is executed, an environment is set up with supporting
information.

**Variables**

`B_ARCH`

This variable contains the architecture the build process is run on.

`B_NAME`

This variable contains the name of the recipe being run.

**Functions**

`B_GITVER <git repostiory> [filter]`

This function attempts to remotely find the newest tag for a git repository. It filters
out some commonly used tags that indicate non-release tags. 
Optionally a filter option can be giving which will be used to filter out any other
tags that should not be used.
The function return the newest tag it can find.

`B_GITHUBVER <github repository>`

This function attempts to find the last date an update was done on a repository on
github. For projects not using tags, this allow for builds to be created on a date
stamp.
The function returns the newest date it can find.

## BUILD

For building the version of the software the following sections are used:

`[REQUIRED]` (optional)

This section can contain a single line of space seperated package names that need to be
installed before the build is attempted.

`[BUILD]` (mandatory)

Everything in this section is executed to build the software. Execution takes place
in a temporary directory. Creation and cleanup of the directroy is handled by the
build script.

Before the code is executed, an environment is set up with supporting information.

**Variables**

`B_ARCH`

This variable contains the architecture the build process is run on.

`B_VERSION`

This variable conains the version of the software that is being build.

`B_INSTALLDIR`

This variable points to the installation directory where the results of the build
need to be placed. This directory is empty and is regarded the root of the target
installation. If a build creates a binary that needs to end up in /usr/bin, the following
actions need to be taken:

`mkdir -p $B_INSTALLDIR/usr/bin; cp binary $B_INSTALLDIR/usr/bin`

`B_ARCH`

Architecture software is being build for.

`B_INSTANCE`

Instance name of software being build. This is only set if an instance was provided on
the invokation of the build script.

`B_CACHEDIR`

This variable points to the download directory for this specific software.

`B_NAME`

This variable contains the name of the software that needs to be build.

`B_BUILDNR`

This variable contains the number of times this specific version of the software has
ben build. This number is also used when creating a package of a build to indicate
a new package of the same version.

`B_FILES`

If a recipe has a recipe specific directory which contains a directory called
`B_FILES`, this variable will point to that directory.  This directory can be
used to store files used during the build process.

**Functions**

`B_GET`

Download software and check if it is already in the cache.
This function supports http and git. The usage is:

B_GET method url target

Retrieving software from a website could be like this:

B_GET http https://software.com/path/v${B_VERSION}/software-${B_VERSION}.tar.gz software.tar.gz


`B_UPDATEPKGBLD`

Update package build number

`B_LINKFILES`
Will link files with the exception of files ending in .real

## PACKAGE

[PKG] (optional for package building)

This section contains some meta information on the type of package that needs
to be build from the result of the BUILD section of the recipe. The following
options can be specified:

type=<pacakge type>
This specifies the type of package that should be build. Currently supported
is:
  deb

torepo=<y|n>
When set to y the package will be pushed to a repository after the package is
created.

configfiles
Specify configfiles


## TO REPOSITORY

# FILES

`~/.buildrc`

Configuration file

# EXAMPLES

for all recipes where there are new versions, build, package and push to repo.

`build -b -p -r -a`

# AUTHOR

Written by Mark Verboom

# REPORTING BUGS

Prefferably by opening an issue on the github page.

# COPYRIGHT

Copyright  ©  2014  Free Software Foundation, Inc.  License GPLv3+: GNU
GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
This is free software: you are free  to  change  and  redistribute  it.
There is NO WARRANTY, to the extent permitted by law.

