# NAME

build - automate building of software

# SYNOPSIS

`build [OPTION]... [RECIPE]...`

# DESCRIPTION

Automates the building of software, although it should be considered alpha
quality software at best.

The building process is described by recipe files which are explained in the
recipe section.

The name of a recipe can be appended by a version number. In that case all actions
will take place for that version and not for the latest available version. A
version number must be prepended by an @ sign.

Example: `test@1.0.0`

The name of a recipe can be appended by an instance designator. This designator
will be appended to the version and is available in the environment during the
build process. This can be used to create specific versions of software based
on different configuration files (for example kernel configuration). The example
below uses an instance of global.

Example: `test:global`

Version and instance can be combined in any order. The following examples are
all valid

Example: `test@1.0.0:global`
         `test:lan@5.1`
         `test@3.0`
         `test:network`

Arguments that can be used are divided into two types:

**Operational mode:**

`-c`
Check version, runs the version check section of the specified recipe(s).

`-b`
Build, runs the build version of the specified recipe(s).

`-p`
Package, runs the package section of the specified recipe(s).

`-r`
To repository, creates packages and copies to repository for specified recipe(s).

**Operation modifiers:**

`-a`
Process all recipes in the recipe directory. Recipes that are not for the current systems
architecture or don't have a build section for this system will be excluded.

`-A`
Filter recipes that are specific for this systems architecture. Skip all other
architecture and recipes for any architecture.

`-f`
Force build for recipe, even if complete build is already available.

`-h`
Show help message.

`-l`
Dry run. Check version information, but do not build, package or push to repo.

`-q`
Quiet output.
Specify once will still show output on successful and failed builds.
Specify twice will not show output.

`-R`
Do not remove required packages after build and skip any post build script.

`-s`
When build of a recipe fails, drop into a shell so the build environment can be
examined.

`-x`
Enable debugging output

# CONFIGURATION FILE

The script uses a configuration file which is located at:

`~/.buildrc`

An example (`buildrc.example`) is included in the repository.

The file has the following format:

`VARIABLE=value`

When using build on multiple systems, it can be advisable to make certain
configuration items host specific in order to avoid collisions between the
systems. Most notable variables are:
* `DESTDIR`
* `LOGDIR`
* `PKGDIR`

The following variable can be set in the configuration file.

`DESTDIR` (defaults to ~/build)
Destination directory where compiled software should be put.

`DESTSPLIT` (defaults to n)
If this option is set, a folder per recipe will be created in which all
versions that are build will be placed. If the option is not set, the recipe 
name and version will be concatenated and used as directory name.

`CACHEDIR` (defaults to ~/cache)
Download cache directory where downloaded files are placed.

`TMPDIR` (defaults to ~/temp)
Temporary directory where the software building takes place.

`LOG` (defaults to ~/log)
Log directory where output of the build process for each build is stored.

`RECIPEDIR` (defaults to ~/recipes)
Directory with recipe files.

`PKGLIST` (defaults to RECIPEDIR/pkglist-$HOSTNAME)
File used for package administration. The hostname of the system building is
appended to provide for seperation when multiple systems use the same environment.

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

`PKGORG`
This optional parameter defines an organisation name. The value of this
parameter will be substituted when B_ORG is used in the [DEB] section of the recipe.

`PKGMAIL`
This optional parameter defines an email address. The value of this
parameter will be substituted when B_MAIL is used in the [DEB] section of the recipe.

`POSTBUILD`
This can point to an optional script to be run after the build process is
complete. The included debclean script can for example be used here.

`PROXY`
Point to a proxy hostname and port to use when connecting to network resources.

`MAXBUILDKEEP`
Maximum number of successful builds to keep. If not set, no limit is imposed, but
could result in loads of diskspace used. This is based on latest successful builds,
not the version number.

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

arch

This is a comma separated list of architectures this recipe should be run for.
If this is absent, the recipe will be run on any architecture.
A recipe that creates a build that can be build and ran on any architecture can
be identified with `all`.

excludefromall

If this option is set to 1, the recipe will not be included when running the build
script with the -a flag. This can be useful for recipes under development, not ready
to include in a nightly run.

intancereq

If this option is set to 1, it indicates this recipe requires an instance to be
passed for it to work. When no instance is passed to this recipe an error will
be generated.

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

`B_GITDATE <git repository>`

Retrieves the last commit date on head for the git repository.

`B_GITVER [option] <git repository>`

This function attempts to remotely find the newest tag for a git repository. It filters out some commonly used tags that indicate non-release tags. The processing
of the output goes through the following stages:
* Retrieve tags from git repository
* Apply optional regular expression (pre-regex) to shape the output
* Apply optional removal filter (pre-filter), removes all chars matching pattern
* Apply optional include filter (include), includes only matches
* Apply optional exclude filter (exclude), excludes all matches
* Apply optional removal filter (post-filter), removes all chars matching pattern
* Apply optional regular expression (post-regex) to shape the output

The command has options to process the raw output and mold it into something useful.

`-r <regex>`:  pre-regex in sed style, like "s/K12/K-1/g" (can be used multiple times)

`-f <filter>`:  pre-filter. Sed style pattern which will be removed, like "-beta" (can be used multiple times)

`-i <pattern>`: include. Only allow lines matching the pattern (grep style). (can be used multiple times)

`-e <pattern>`: exclude. Remove all lines matching the pattern (grep style). (can be used multiple times)

`-F <filter>`:  post-filter. Sed style pattern which will be removed, like "-beta" (can be used multiple times)

`-R <regex>`: post-regex in sed style, like "s/_/\./g" (can be used multiple times)

`-a`: Don't apply default removal filter (post-filter), like rc, beta etc

`-D`: Write the complete command to `/tmp/b_gitver`.

The function return the newest tag it can find.

`B_GITHUBVER <github repository uri> <branch>`

This function attempts to find the last date an update was done on a repository on
github. For projects not using tags, this allow for builds to be created on a date
stamp.
The function returns the newest date it can find. When <branch> is not supplied, it will look in master.

Github's core API is rate-limited to 60 requests per hour, as of now there is no way to increase it.

Example: `B_GITHUBVER https://github.com/user/repo`
         `B_GITHUBVER https://github.com/user/repo branch`

`B_GITHUBREL <github repository uri>`

This function uses the github api to determine the latest release of the project
that was published.

Example: `B_GITHUBREL https://github.com/user/repo`

`B_GITLABVER <gitlab repository uri> <branch>`

This function attempts to find the last date an update was done on a repository on
gitlab. For projects not using tags, this allow for builds to be created on a date
stamp.  The function returns the newest date it can find.

When <branch> is not supplied, it will look in master.

Example: `B_GITLABVER https://gitlab.com/user/repository`
         `B_GITLABVER https://gitlab.com/user/repository branch`

`B_SVNDATE <svn repository>`

This function attempts to find the last date an update was done on an subversion
repository.

`B_SVNREV <svn repository>`

This function attempts to find the last revision number for the subversion
repository specified.

`B_HGREV <mercurial repository>`

This function attempts to find the last revision number for the mercurial
repository specified.

`B_SFVER <sourceforce project url>`

This function attempts to find the latest version for a project hosted on
sourceforge.

## BUILD

For building the version of the software the following sections are used:

`[REQUIRED] [REQUIRED DISTRO] [REQUIRED DISTRO RELEASE]` (optional)

This section can contain a single line of space separated package names that need to be installed before the build is attempted.

It is possible to have multiple sections present in the recipe as long as they don't
have the same name. The order in which the section is used is:

* [REQUIRED DISTRO RELEASE]
* [REQUIRED DISTRO]
* [REQUIRED]

The DISTRO and RELEASE keywords are determined based on the machine the script
is running on.

When the name of a package contains B_PF this will be expanded to the value 
of the PKGPOSTFIX variable.

`[BUILD] [BUILD DISTRO] [BUILD DISTRO RELEASE]` (mandatory)

This section is required in the recipe and will be matched to the most specific available option:
* [BUILD DISTRO RELEASE]
* [BUILD DISTRO]
* [BUILD]

Everything in this section is executed to build the software. Execution takes place
in a temporary directory. Creation and cleanup of the directory is handled by the
build script.

Before the code is executed, an environment is set up with supporting information.

**Variables**

`B_METABUILD`

This variable is used when a recipe needs to build other recipes (for meta
recipes).  This variable isn't set, but can be set by the recipe. When the recipe
calls build again, build will skip checking the lockfile.

`B_ARCH`

This variable contains the architecture the build process is run on.

`B_VERSION`

This variable contains the version of the software that is being build.

`B_INSTALLDIR`

This variable points to the installation directory where the results of the build
need to be placed. This directory is empty and is regarded the root of the target
installation. If a build creates a binary that needs to end up in /usr/bin, the following
actions need to be taken:

`mkdir -p $B_INSTALLDIR/usr/bin; cp binary $B_INSTALLDIR/usr/bin`

`B_ARCH`

Architecture software is being build for.

`B_INSTANCE`

Instance name of software being build. This is only set if an instance was
provided on the invocation of the build script.

`B_CACHEDIR`

This variable points to the download directory for this specific software.

`B_NAME`

This variable contains the name of the software that needs to be build.

`B_BUILDNR`

This variable contains the number of times this specific version of the software has
been build. This number is also used when creating a package of a build to indicate
a new package of the same version.

`B_FORCE`

When the build phase of the recipe was forced through -f, this variable will be set to
1.

`B_FILES`

If a recipe has a recipe specific directory which contains a directory called
`B_BUILD`, this variable will point to that directory.  This directory can be
used to store files used during the build process.

**Functions**

`B_GET <method> [method options] <url> <name>`

The B_GET function assists in caching and downloading of content. It supports
different download methods and caches content in the cache directory.

The url should reference the content that needs to be downloaded.

The name references the name of the cache object that needs to be created. For
all methods that support version information, this is also the name of the 
folder that will have been created if the `B_GET` function successfully completes 
operation.

The following methods are supported:

* http

This is used for download http or https content. As this method does not  provide
any version information, the cache directory will be populated with a directory
per version. If `B_GET` completes successfully a file called `name` will be
available. Any unpacking or processing on the downloaded content needs to be
performed by the code in the recipe.

* git

This is used to clone git repositories. This method provides version information.
Only one directory will be created in the cache directory. When a newer version
of the software is detected an update will be done on the previously cached cloned
git repository. The update will be stored back in the cache.
If `B_GET` completes succesfully, a folder called `name` will be available with
the repository content.

This method has the following extra options:

`-s`: Also get submodules for repository.

* svn (subversion, status beta)

This is used to check out subversion repositories. This method is beta and not
completely implemented.
If `B_GET` completes successfully, a folder called `name` will be available with
the repository content.

* hg (mercurial, status beta)

This is used to clone mercurial repositories. This method is beta and not
completely implemented.
If `B_GET` completes successfully, a folder called `name` will be available with
the repository content.

* sf (sourceforge, status beta)

This is used to download the version of the software from sourceforge.

* go

This is used to download a go repositories. This method does not use the <name>
argument, as all go software is downloaded to the `src` directory. Keep in mind
that the url for a go package does not specify the protocol, so no prefix of
http or https for example.
When a newer version of the software is detected an update will be done on the 
previously cached go repository. The update will be stored back in the cache.
If `B_GET` completes successfully, a folder called `src` will be available with
the repository content.
This download method also initialises the following environment variables:
GOROOT GOPATH

`B_GETPKGBLD`

Returns the next sequence of package number to be used for this version of the
package. This can be used in recipes where the build produces a package.

`B_LINKFILES <source directory> <destination directory>`

This function will create symlinks for all files in the source directory to the
destination directory. The destination directory needs to be relative to the
`B_INSTALLDIR`. If the destination directory doesn't exist yet, it is created
automatically.

Any file in the source directory that exists and ends in `.real` will not be
linked.

`B_LINKFILE <source file> <destination directory>`

This function will create a symlink for the source file to the
destination directory. The destination directory needs to be relative to the
`B_INSTALLDIR`. If the destination directory doesn't exist yet, it is created
automatically.

## PACKAGE

Once a package has been created, it will be stored in the `PKGDIR` as specified
in `~/.buildrc`.

For creating a package the following sections are used:

`[PKG]` (mandatory)

This section contains some meta information on the type of package that needs
to be build from the result of the `[BUILD]` section of the recipe. The following
options can be specified:

`type=<package type>` (mandatory)

This specifies the type of package that should be build. Currently supported
types are:
* deb (Debian package)

The type of package specified here implies the relevant section for this package
type needs to exist.

`pkgready=<y|n>` (optional)

If the build section already created a package, don't process any type specific
package section.

`configfiles=<configfile>..` (optional)

Specifies path to any configuration files that are in the build. The paths
need to be relative to the `B_INSTALLDIR` used during build. Only files that do
not reside in a path where the sub part is `*/etc/*` need to be specified here.

`[DEB] [DEB RELEASE]` (mandatory for debian packages)

This section contains information relevant to the creation of a Debian package.
All contents in this section is used to put into the `control` file inside the
package.

There can be multiple DEB sections in the recipe, but they need to include the
release name in the header. The order in which they are evaluated is:

* [DEB RELEASE]
* [DEB]

Release is determined by checking the system the script is run on.

If the recipe directory contains a files directory for the recipe, all files
that are available in the `B_DEBIAN` folder will automatically be included
in the package. It is possible to differentiate based on the release. The order
of check will be:

* B_DEBIAN-RELEASE
* B_DEBIAN

One specific directory `B_DEBIAN/DEBIAN` can contain files used to create the
package, like for example post installation commands. For more information on
this, check the Debian packaging documentation. Any `control` file in the
`B_DEBIAN/DEBIAN` directory will be overwritten by the information in this
section.

A number of substitutions will be made if specific keywords are used in this
section. The available keywords are:

* `B_VERSION`

This will be replaced by the actual version of the package being created.

* `B_ARCH`

This will be replaced by the actual architecture for which the package is
being created.

* `B_PF`

This will be replaced by the value of the PKGPOSTFIX variable if defined in the
configuration.

* `B_INSTANCE`

This will be replaced by the instance requested.

* `B_MAIL`

This will be replaced by the value of the PKGMAIL variable if defined in the
configuration.

* `B_DEPENDS`

This is a special keyword and requires the recipe to contain a section [DEB_DEPENDS].
This section is supposed to generate any dynamic package dependencies. This can be
useful when making meta packages which required specific versions of package build
by other recipes.

`[DEP_DEPENDS]` (optional for debian packages)

This section contains shell code that will be run when a `[DEB]` section contains
the macro `[DEB_DEPENDS]`. The output of the code should be compatible with the
debian package dependency specification.

## TO REPOSITORY

For pushing a package to a repository, there is no specific section.

Depending on the package that is build, the corresponding entry from the `.buildrc`
is used to determine the script that needs to be run to push the package to the
repository.

# FILES

`~/.buildrc`

Configuration file

# EXAMPLES

for all recipes where there are new versions, build, package and push to repo.

`build -b -p -r -a`

# AUTHOR

Written by Mark Verboom

# REPORTING BUGS

Preferably by opening an issue on the github page.

# COPYRIGHT

Copyright  ©  2014  Free Software Foundation, Inc.  License GPLv3+: GNU
GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
This is free software: you are free  to  change  and  redistribute  it.
There is NO WARRANTY, to the extent permitted by law.

