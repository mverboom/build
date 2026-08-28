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
Package, runs the package section of the specified recipe(s).

`-r`
To repository, creates packages and copies to repository for specified recipe(s).

**Operation modifiers:**

`-a`
Process all recipes in the recipe directory. Recipes that are not for the current systems
architecture or don't have a build section for this system will be excluded. Recipes
that require an instance (see `instance` in their `[INFO]` section) are skipped unless an
instance is given with `-i`.

`-l`
Dryrun. Only reports which recipes would be built, packaged and/or pushed to the
repository, without executing any of it. No lock is taken and nothing is written
(cache, build output, package list) — useful to preview what `build -a` would do.

A recipe name given on the command line may be suffixed with a forced version and/or
instance, in either order:

```
recipe                  use the recipe's own version check
recipe@version          build a specific version (skips the recipe's version check)
recipe:instance         build for a specific instance
recipe@version:instance both (also recipe:instance@version)
```

This lets you build several recipes at different versions and/or instances in a single
command, e.g. `build -bp -d trixie foo@1.2.3 bar:dev baz@4.5.6:prod`.

`-q`
Quiet output.
Specify once will still show output on succesfull and failed builds.
Specify twice will not show output.

`-v`
Verbose output. Show command output that is normally suppressed (e.g. the
`apt-get update`/`apt-get install` run by the container entrypoint to install
build dependencies). Errors from such commands are always surfaced (and written
to the build log) even without `-v`; `-v` additionally shows the full successful
output.

`-x`
Enable debugging output

`-s`
When build of a recipe fails, drop into a shell so the build environment can be
examined.

`-f`
Force build for recipe, even if complete build is already available.

`-d`
Specify the target distribution for the Docker build (e.g., `trixie`, `bookworm`).
Required on the host, since builds always run inside Docker. Inside the `-S` dev
shell container it is optional and defaults to the container's distribution.
A bare codename is equivalent to the family-codename form (`-d trixie` selects
`[REQUIRED DEBIAN TRIXIE]` sections just like `-d debian-trixie`).

`-i`
Specify an instance for a recipe. Applies to all recipes on the command line unless a
recipe overrides it with the `recipe:instance` suffix.

`-R`
Do not remove required packages after build and skip any post build script.

`-h`
This help message

**Docker interactive commands:**

`-S`
Shell, start an interactive development shell in a Docker container for the
specified distro (e.g., `-S bookworm`, `-S trixie`). Inside the shell, builds run
natively on the container's system (there is no Docker-in-Docker).

`-A`
Attach, re-attach to a running Docker container by container ID (e.g., one kept
alive after a failed build with `-s`).

# BUILD MODE

Builds always run inside Docker containers. The host only orchestrates
`docker run`; it does not execute recipe BUILD sections directly and does not
install or remove build dependencies on the host. Build dependencies are
installed inside the container (which is ephemeral) by the container
entrypoint, using the package list collected from the recipe's `[REQUIRED]`
section.

`INSTDEP` / `DEINSTDEP` therefore only take effect inside the `-S` dev shell
container, where builds run natively.

The target distribution is set with `-d` / `BUILDDISTRO` and is required on the
host. Custom Docker images live in the `docker/` directory (build them with
`docker build -t build-<distro>:latest -f docker/Dockerfile.<distro> docker`).

The container's apt configuration (repositories, proxies, signing keys and
credentials) is generated from build configuration only -- it does not
inherit anything from the host OS's `/etc/apt`. See the APT / REPOSITORIES
section below.

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

`MAXCACHEKEEP` (defaults to 3)
Number of versioned download versions to keep per package in the cache. After
each build session the oldest versioned downloads (B_GET http/sf) are pruned so
the cache does not grow without bound. Single-file caches (git/go/hg/svn
tarballs, which avoid re-cloning on every build) are never removed. Set to 0 or
empty to disable pruning. See also the `cacheclean` script for on-demand
reporting and management of the cache.

`MAXBUILDKEEP` (defaults to 1)
Number of built versions to keep per package in the build output directory
(DESTDIR). After each build session the oldest build output directories are
pruned so the build output does not grow without bound. Set to 0 or empty to
disable pruning.

`BUILDKEEPTIME` (defaults to 0, keep all)
Build-time cutoff in seconds for keeping build output after packaging. Builds
that take at least this long keep their full output in the build directory, so
a packaging-only recipe change can be re-packaged without a full rebuild.
Faster builds have their output replaced with an empty marker directory (the
version is still recorded as built, but a rebuild is cheap and re-packaging of
that output requires a rebuild). Set to 0 or empty to keep all build output.

`TMPDIR` (defaults to ~/temp)
Temporary directory where the software building takes place.

`LOG` (defaults to ~/log)
Log directory where output of the build process for each build is stored.

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

The target repository can be derived from the `B_DISTRO` environment variable
(see below), which `build` exports for the script. This is the platform-
agnostic codename of the distro being built for (e.g. `trixie`, `bookworm`),
so a single `TODEBREPO` script can select the right repository without relying
on the build host's hostname.

`INSTDEP` (defaults to yes)
If set to yes will try to install the required packages specified in the
recipe for the build. On the host this happens inside the Docker container via
the entrypoint; inside the `-S` dev shell it requires the user running the
script to have sudo rights to install packages.

`DEINSTDEP` (defaults to yes)
if set to yes will try to remove the packages that were required for the
build process. Only relevant inside the `-S` dev shell (host builds run in
ephemeral containers, so nothing to remove); requires sudo rights to remove
packages.

`PKGPOSTFIX`
This optional parameter defines an addition to the package name and can help
identify package build by the script in a repository or system.

`PKGORG`
This optional parameter defines an organisation name. The value of this
parameter will be substituted when B_ORG is used in the [DEB] section of the recipe.

`PKGMAIL`
This optional parameter defines an email adress. The value of this
parameter will be substituted when B_MAIL is used in the [DEB] section of the recipe.

`POSTBUILD`
This can point to an optional script to be run after the build process is
complete. The included clean script can for example be used here. If the
postbuild command fails, the build is treated as failed: the build output is
removed and the recipe is reported as failed.

`PROXY`
Point to a proxy hostname and port to use when connecting to network resources.
This is a generic, optional proxy: it is passed to containers as the
`http_proxy`/`https_proxy` environment variables and is used by generic
commands (`B_GET`, `wget`, `git`, ...). It is not mandatory; if unset, the
build connects directly. A per-distro override is possible (see
APT / REPOSITORIES).

`BUILD_REPOS_DIR`
Directory holding per-distro apt/repository configuration files (defaults to
`~/.build-repos.d`). See the APT / REPOSITORIES section.

# APT / REPOSITORIES

Docker builds **never** read the host OS's `/etc/apt` configuration
(repositories, proxies, signing keys, credentials). All of that comes either
from the standard Debian defaults or from per-distro configuration files.

For each target distribution there may be a configuration file, named after the
bare codename (`~/.build-repos.d/trixie`) or the family-codename
(`~/.build-repos.d/debian-trixie`). The file is a sourced bash script. If no
file exists for a distro, the standard Debian default repositories are used
with no custom proxy. An example is included as `build-repos-example`.

The following may be set in a per-distro file:

`PROXY`
Optional distro-specific generic proxy. Overrides the global `PROXY` from
`~/.buildrc` for builds of this distro.

`NO_DEFAULT_REPOS`
Set to `1` to drop the standard Debian default repositories and use only the
custom repositories declared below. Default `0` (defaults are kept).

`DEFAULT_REPOS`
Multi-line text written verbatim as a sources `.list` file, used in place of
the Debian defaults. Only meaningful with `NO_DEFAULT_REPOS=1`.

Custom repositories are declared with the `repo` helper, one per line:

    repo <id> key=value ...

The fields are:

`url=`         repository URL (required)

`suite=`       distribution suite / codename (required)

`components=`  space-separated components (default `main`)

`proxy=`       per-repository proxy URL, or `DIRECT` to bypass the generic
proxy for this repository's host. This overrides the `PROXY` for apt traffic
to this repository only.

`auth=`        HTTP basic auth credentials as `user:password`, applied to the
repository host.

`authfile=`    path to an apt `auth.conf.d` credentials file. Relative paths
resolve against the per-distro config file's directory.

`key=`         signing key: `file:<path>` (relative to the config dir or
absolute), `url:<https-url>`, or a plain `https://` URL. The key is imported
into the container keyring as `/etc/apt/keyrings/<id>.gpg`.

`signedby=`    apt `signed-by` key id (alternative to `key=`).

`arch=`        restrict the repository to architectures (e.g. `amd64,arm64`).

Example:

    PROXY="http://proxy.example.net:8080"
    repo internal \
      url=https://repo.example.net/debian suite=trixie components="main contrib" \
      auth=builduser:s3cret key=file:./keys/repo-example-net.asc
    repo direct-host \
      url=https://repo.verboom.net/debian suite=trixie proxy=DIRECT \
      key=https://repo.verboom.net/key.asc

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

A recipe is built up in .ini file style format. Each section has a specific name
and contains the information required for its function. Not every section is
mandatory.

Sections in recipes not related to an operation mode are:

`[INFO]` (optional)

The following options can be set:

arch

This is a comma seperated list of architectures this recipe should be run for.
If this is absent, the recipe will be run on any architecture.
A recipe that creates a build that can be built and ran on any architecture can
be identified with `all`.

excludefromall

If this option is set to 1, the recipe will not be included when running the build
script with the -a flag. This can be useful for recipes under development, not ready
to include in a nightly run.

The following optional keys enable source-integrity checks at fetch time
(see `SECURITY.md` group A):

gpgkey

A GPG key fingerprint or key id used to verify the signature on the git tag
checked out by `B_GITCHECKOUT` (A1). When set, the tag must carry a valid
signature made by this key or the build fails. When the `STRICT` configuration
option is enabled, git-based recipes without a `gpgkey` are refused.

gpgkeyfile

Path to an exported public key file (ASCII-armoured or binary) for the key
named by `gpgkey`. If the path is relative, it is resolved against `B_FILES`
(the recipe's `.files/B_BUILD` directory). `B_GITCHECKOUT` imports this file
with `gpg --import` before verifying the tag, so signature verification works
in build environments that cannot reach public keyservers. If `gpgkeyfile`
is omitted, `B_GITCHECKOUT` falls back to fetching the key from keyservers.

commit

A 40-character commit SHA. When set, `B_GITCHECKOUT` refuses to build unless
the resolved ref matches this exact commit (A2). This makes what was built
deterministic and auditable, independent of movable tags.

sha256

The expected SHA-256 digest of an asset fetched with `B_GET http` or
`B_GET sf` (A3). When set, the downloaded (or cached) file is verified with
`sha256sum` before it is used; a mismatch fails the build.

allow_insecure

Set to 1 to explicitly allow plain `http://`, `git://` or `svn://` fetches
that would otherwise be rejected by the HTTPS-only enforcement (A4). Use only
for sources that have no encrypted transport available.

gittag

The exact git tag to shallow-fetch for a `B_GET git` recipe whose version tag
is not named `v$B_VERSION` or `$B_VERSION` (e.g. termix uses
`release-$B_VERSION-tag`). The value may reference `$B_VERSION` (and other
exported build variables); it is expanded at fetch time. Without this key,
`_b_git_refresh` only fetches `v$B_VERSION`/`$B_VERSION`, so a recipe that
checks out a differently-named tag would fail with a "pathspec did not match"
error.

Security-scan policy and exceptions (vulnscan, vulnscan-ignore, srcguard,
srcguard-ignore) live in the `[SECURITY]` section — see below.

## SECURITY

All security-scan policy and per-issue/per-file exceptions live in the
optional `[SECURITY]` section. The two scans (vulnerability scan and static
build-script guard) run automatically after the `[BUILD]` section; recipes do
not need to call them themselves. Global defaults can be set in `~/.buildrc`
(`VULNSCAN=`, `SRCGUARD=`); a recipe's `[SECURITY]` value overrides the global
default; if neither is set, the scan does not run.

vulnscan

Enables automatic vulnerability scanning of the resolved build-time
dependencies (see `SECURITY.md` group F4). After the `[BUILD]` section runs,
the build tree is scanned with `osv-scanner` (baked into the Docker base
image) for known vulnerabilities in lockfiles/manifests (npm, pip, cargo, go,
maven, etc.). Supported values:

- `advisory` — report findings but never fail the build.
- `enforce` — fail the build if any HIGH or CRITICAL severity vulnerability
  is found.

vulnscan-ignore

Comma-separated list of vulnerability IDs to suppress (any ID osv-scanner
reports: `GHSA-*`, `CVE-*`, `PYSEC-*`, `GO-*`, ...). The key may be repeated
to split the list over multiple lines; all lines are merged. The build script
turns the list into an osv-scanner config that is applied to the whole scan,
so `vulnscan=enforce` stays active for everything else. Use comment lines
above the key to document why each exception exists.

srcguard

Enables a static guard that scans the fetched source tree for suspicious
build-script patterns (see `SECURITY.md` group F6): network access or
embedded-blob decoding inside `configure`/`*.m4`/`CMakeLists.txt`/`Makefile`/
`package.json` scripts — the XZ/liblzma signature. Supported values:

- `advisory` — report findings but never fail the build.
- `enforce` — fail the build if any suspicious pattern is found.

It is heuristic and may produce false positives, so `advisory` is
recommended when a recipe cannot allow-list its expected hits.

srcguard-ignore

Comma-separated list of file paths (relative to the build root) to suppress
from the srcguard scan. All hits in an ignored file are skipped, so
`srcguard=enforce` stays active for everything else. The key may be repeated
to split the list over multiple lines; all lines are merged. Use comment
lines above the key to document why each exception exists.

Example:

```
[SECURITY]
# framework_uefi/Makefile (not built) downloads UEFI shell/OVMF firmware via
# curl from official sources. Legitimate build-time downloads, not the XZ
# pattern.
srcguard=enforce
srcguard-ignore=framework-system/framework_uefi/Makefile
# proc-macro-error2 (transitive build-time dep via clap_derive) is
# unmaintained; informational advisory, no patched version exists.
vulnscan-ignore=RUSTSEC-2026-0173
```

When a scan finds findings, the build log always prints a copy-pasteable
`[SECURITY]` block listing the reported IDs/files, so exceptions are easy to
add straight from the log output (trim the list to the findings you have
reviewed).

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

`B_GITDATE <git repository> <branch>`

This function retrieves the last commit date on the head of the given branch of a git
repository and returns it as a date stamp (`%Y%m%d`). When <branch> is not supplied, it
will look in master.

Note that this function reads the commit object over plain HTTP (the git "dumb HTTP"
protocol); it only works with repositories served over HTTP(S) that support it.

Example: `B_GITDATE https://github.com/user/repo`
         `B_GITDATE https://github.com/user/repo branch`

`B_GITHUBREL <github repository uri>`

This function uses the GitHub API to determine the tag of the latest release
published for the project. A leading `v` is stripped from the tag.

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

`B_SFVER <sourceforce project url>`

This function attempts to find the latest version for a project hosted on
sourceforge.

## BUILD

For building the version of the software the following sections are used:

`[REQUIRED] [REQUIRED DISTRO] [REQUIRED DISTRO RELEASE]` (optional)

This section can contain a single line of space seperated package names that need to be installed before the build is attempted.

It is possible to have multiple sections present in the recipe as long as they don't
have the same name. The order in which the section is used is:

* [REQUIRED DISTRO RELEASE]
* [REQUIRED DISTRO]
* [REQUIRED]

The DISTRO and RELEASE keywords are determined based on the machine the script
is running on.

When the name of a package contains B_PF this will be expanded to the value 
of the PKGPOSTFIX variable. When it contains B_INSTANCE this will be expanded
to the instance given on the invokation of the build script (if any).

`[BUILD] [BUILD DISTRO] [BUILD DISTRO RELEASE]` (mandatory)

This section is required in the recipe and will be matched to the most specific available option:
* [BUILD DISTRO RELEASE]
* [BUILD DISTRO]
* [BUILD]

Everything in this section is executed to build the software. Execution takes place
in a temporary directory. Creation and cleanup of the directroy is handled by the
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

Instance name of software being build. This is set when an instance was provided on
the invokation of the build script, either globally via `-i` or per recipe via the
`recipe:instance` command-line suffix (the per-recipe value takes precedence).

`B_PF`

The value of the `PKGPOSTFIX` configuration variable. Available as a variable
(so `$B_PF` can be used in BUILD commands) in addition to the keyword
substitution in the `[DEB]`, `[REQUIRED]` and `[DEB_DEPENDS]` sections.

`B_CACHEDIR`

This variable points to the download directory for this specific software.

`B_NAME`

This variable contains the name of the software that needs to be build.

`B_BUILDNR`

This variable contains the number of times this specific version of the software has
ben build. This number is also used when creating a package of a build to indicate
a new package of the same version.

`B_FORCE`

When the build phase of the recipe was forced through -f, this variable will be set to
1.

`B_DISTRO`

The target distribution codename for the build (e.g. `trixie`, `bookworm`). It
is a platform-agnostic identifier derived from `-d` / `BUILDDISTRO` in Docker
mode, or from the running system's `lsb_release` in native mode. It is exported
so that the `TODEBREPO` publish script (and any other post-build hook) can
select the target repository without having to infer it from the package
filename or the build host's hostname.

`B_FILES`

If a recipe has a recipe specific directory which contains a directory called
`B_BUILD`, this variable will point to that directory.  This directory can be
used to store files used during the build process.

**Functions**

`B_GET <method> [method options] <url> <name>`

The B_GET function assists in caching and downloading of content. It supports
different download methods and caches content in the cache directory.

As a supply-chain safeguard (SECURITY.md group A4), `B_GET` enforces encrypted
transport: URLs must use `https://`, `git@`, `ssh://`, `svn+ssh://` or
`file://`. Plain `http://`, `git://` and `svn://` URLs are rejected unless the
recipe sets `allow_insecure=1` in its `[INFO]` section. `wget` calls use
`--secure-protocol=TLSv1_2` and `--https-only` (when insecure fetches are not
allowed). For `http` and `sf` methods, an `[INFO]` `sha256=` value is verified
against the fetched asset (A3).

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
If `B_GET` completes successfully, a folder called `name` will be available with
the repository content.

The clone is **shallow** (`git clone --depth 1`): only the default-branch tip and
the current version tag are fetched, not the full repository history. This keeps
the cache small (the full history is typically ~90% of a clone's size). Tag-based
recipes (`git checkout v$B_VERSION`) and date-based recipes (which build the
default-branch head) both work from the shallow clone. On each build the cached
clone is refreshed shallowly to the latest default-branch tip and the current
version tag.

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

`B_GITCHECKOUT <ref>`

Verifies and checks out a git tag or ref with source-integrity enforcement
(SECURITY.md group A1 & A2). Use it in place of a bare
`git checkout tags/v$B_VERSION` so that tag signatures and pinned commits are
checked. The `<ref>` may be given as `v$B_VERSION` or `tags/v$B_VERSION`.

When `[INFO]` `gpgkey=` is set, the tag signature is verified with `git
verify-tag` and must be made by the declared key (A1); otherwise the build
fails. When `[INFO]` `commit=` is set, the resolved `HEAD` must match that
SHA exactly (A2). In `STRICT` mode, a git checkout without a `gpgkey` is
refused.

`B_VULNSCAN [path]`

Scans the build tree for known vulnerabilities in resolved build-time
dependencies (SECURITY.md group F4) using `osv-scanner`. It is run
automatically after the `[BUILD]` section when the `[SECURITY]` `vulnscan=`
key is set, so recipes normally do not need to call it. The optional `path`
argument overrides the default scan target (the build root). Behaviour is
controlled by `vulnscan=advisory` (warn only) or `vulnscan=enforce` (fail on
HIGH/CRITICAL). Per-issue exceptions from the recipe's `[SECURITY]`
`vulnscan-ignore=` key are applied to the scan automatically (see the
`vulnscan` section above).

`B_SRCGUARD [path]`

Scans the build tree for suspicious build-script patterns (SECURITY.md group
F6): network access or embedded-blob decoding inside `configure`/`*.m4`/
`CMakeLists.txt`/`Makefile`/`package.json` scripts. It is run automatically
after the `[BUILD]` section when the `[SECURITY]` `srcguard=` key is set, so
recipes normally do not need to call it. The optional `path` argument
overrides the default scan target (the build root). Behaviour is controlled by
`srcguard=advisory` (warn only) or `srcguard=enforce` (fail on any hit).
Per-file exceptions from the recipe's `[SECURITY]` `srcguard-ignore=` key
(paths relative to the build root) are filtered out automatically (see the
`srcguard` section above). Heuristic; may produce false positives.

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

A SLSA-style provenance sidecar (see `SECURITY.md` group D1) is written next
to each package as `<pkgfile>.provenance.json`, recording the recipe name,
version, arch, distro, package SHA-256, build number, recipe-dir git HEAD,
source-integrity pins (`commit`/`gpgkey`/`sha256`), Docker image ID, real
build host, a sorted `dpkg-query` snapshot of installed packages, and a UTC
timestamp. It is best-effort and never fails the build.

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

* `B_DEBIAN-<RELEASE>` (e.g. `B_DEBIAN-BOOKWORM`)
* `B_DEBIAN`

One specific directory `B_DEBIAN/DEBIAN` can contain files
used to create the package, like for example post installation commands. For
more information on this, check the Debian packaging documentation. Any `control`
file in the `B_DEBIAN/DEBIAN` directory will be overwritten by the information
in this section.

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

This will be replaced by the instance given on the invokation of the build
script (if any).

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

The code is run with `B_VERSION`, `B_INSTANCE` and `B_PF` set in its environment,
so instance-specific or postfix-specific dependencies can be generated.

## TO REPOSITORY

For pushing a package to a repository, there is no specific section.

Depending on the package that is built, the corresponding entry from the `.buildrc`
is used to determine the script that needs to be run to push the package to the
repository.

# FILES

`~/.buildrc`

Configuration file

# CACHE MANAGEMENT

The download cache (`CACHEDIR`, default `~/cache`) holds two kinds of entries:

* **versioned downloads** (B_GET http/sf) - one file per version, e.g.
  `freecad-1.0.2`, `freecad-1.1.0`, ... These accumulate without bound.
* **single-file caches** (B_GET git/go/hg/svn) - a tarball per package that is
  updated in place. These are the efficiency cache that avoids re-cloning on
  every build and must be kept.

`build` prunes stale versioned downloads automatically after each build session,
keeping the `MAXCACHEKEEP` most recently downloaded versions per package. The
single-file git tarballs are never touched, so build efficiency is preserved.

For on-demand reporting and management, use the `cacheclean` script:

`cacheclean`

Print a usage report: total cache size, breakdown by cache type, top
consumers, and how much a prune would free.

`cacheclean --prune [N]`

Prune stale versioned downloads, keeping the N newest per package (default:
`MAXCACHEKEEP` from `~/.buildrc`, or 3). Single-file git tarballs are never
removed. Add `--dry-run` to preview without deleting.

`cacheclean --compact`

Compact single-file git tarballs with `git gc` to reclaim space from
unreachable objects (e.g. force-moved tags). Slow on large caches; run
sparingly.

`cacheclean --orphans`

Remove cache directories for packages that no longer have a recipe. Add
`--dry-run` to preview.

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

