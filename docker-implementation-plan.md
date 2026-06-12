# Docker Implementation Plan for Build

This document provides a detailed, phased implementation plan for adding Docker support to the Build system. It incorporates findings from `docker-research.md`, the bash skill improvements from `improvement.md`, and the RPM support gaps documented in `MULTI.md`.

Each phase is designed to be **independently useful and deployable** — you can stop after any phase and have a working system.

---

## Phase 0: Bash Skill Compliance & Code Cleanup

**Goal:** Fix the bash skill violations and code quality issues identified in `improvement.md` before making structural changes. This makes the codebase easier to work on and prevents compounding technical debt.

**Why first:** Every subsequent phase modifies the same scripts. Fixing the fundamentals now means all future changes start from a clean baseline.

### Tasks

#### 0.1 Shebang and set options (all scripts)

| File | Change |
|------|--------|
| `build` | Change `#!/bin/bash` → `#!/usr/bin/env bash`; add `set -u` |
| `torepo` | Change `#!/bin/bash` → `#!/usr/bin/env bash`; replace `set -e` with `set -u` |
| `clean` | Change `#!/bin/bash` → `#!/usr/bin/env bash`; add `set -u` |
| `debclean` | Change `#!/bin/bash` → `#!/usr/bin/env bash`; add `set -u` |

#### 0.2 Quote all variable expansions (all scripts)

Fix all SC2086 shellcheck warnings. Every variable expansion must be double-quoted unless word splitting is explicitly desired. Key areas:

- `build`: `${work_built[$i]}`, `$DO_CHECK`, `$B_FORCE`, `$missing`, `${PIPESTATUS[*]}`
- `torepo`: `$pkg`, `$SERVER`, `$REPONAME`, `$flags`, `$filename`
- `clean`: `$BASE`, `$CUR`, `${BASH_SOURCE[0]}`, `${PIPESTATUS[3]}`
- `debclean`: same pattern as `clean`

#### 0.3 Replace `test` with `[[` and use `(( ))` for arithmetic (all scripts)

- Replace `test ... -eq ...` with `(( ... == ... ))` for numeric comparisons
- Replace `test -f`, `test -d`, `test -n`, `test -z` with `[[ -f ]]`, `[[ -d ]]`, etc.
- Replace `test "$var" = "value"` with `[[ "$var" == "value" ]]`

#### 0.4 Replace `echo` with `printf` (all scripts)

- Replace `echo "message"` with `printf '%s\n' "message"`
- Replace `echo -n "message"` with `printf '%s' "message"`
- Replace `echo -e "message"` with `printf '%b\n' "message"`

#### 0.5 Replace `eval` with safe alternatives

| File | Current | Replacement |
|------|---------|-------------|
| `build` (main) | `OS=$(grep "^NAME" /etc/os-release); eval "${OS/*=/OS=}"` | `source /etc/os-release` |
| `clean` | `eval ${os/*=/os=}` | `source /etc/os-release` |

#### 0.6 Use `return` instead of `exit` in functions

The `build` script uses `exit 1` inside `B_GET()`, `B_LINKFILES()`, `B_LINKFILE()`, and other functions. Replace all with `return 1` so callers can handle errors.

#### 0.7 Add `main` function to `torepo`, `clean`, `debclean`

Wrap all top-level logic in a `main()` function following the bash skill structure:
1. shebang
2. set options
3. global variables and constants
4. utility functions
5. domain functions
6. main function
7. call to main

#### 0.8 Use `local` for function-scoped variables

Audit all functions and add `local` to variables that don't need to be global. Key offenders:
- `build`: `versiondir` in `build()`, `ver` in `version_get()`
- `torepo`: `ret`, `filename`
- `clean`: `answer`
- `debclean`: `answer`

#### 0.9 Add `trap` for temp file cleanup

- `build()`: Add `trap 'rm -rf "$TMP"' EXIT` after `mktemp`
- `clean`: Add trap for `$CUR` cleanup
- `debclean`: Same as `clean`

#### 0.10 Fix `read` without `-r`

- `clean` and `debclean`: Change `read answer` to `read -r answer`

#### 0.11 Use `"$@"` instead of `$*`

- `torepo`: Change `for pkg in $*` to `for pkg in "$@"`

#### 0.12 Fix documentation typos

Fix all typos listed in `improvement.md` section 3.11 across all `.md` files and inline comments.

#### 0.13 Remove dead code

- Remove `recipe_check_builddistro()` from `build` (identical to `recipe_select_arch()`, never called)
- Keep `package_rpm()` stub but add a TODO comment (will be implemented in Phase 3)

### Validation

- [ ] All four scripts pass `bash -n` syntax check
- [ ] All four scripts pass `shellcheck` with zero errors/warnings (or documented exceptions)
- [ ] All existing recipes build successfully in native mode
- [ ] `build -c -a` still works
- [ ] `build -b -p build` still produces a valid `.deb`

---

## Phase 1: Docker Infrastructure — Build Phase Only

**Goal:** Add Docker support for the build phase (`-b` flag). The build script detects `BUILDMODE=docker`, starts a container with the appropriate base image, runs the BUILD section inside it, and collects results from mounted volumes. Native mode remains the default and works unchanged.

**Why this phase first:** This is the highest-value change — it eliminates the need for separate machines per distro. The build phase is where most of the distro-specific work happens. Version checking and packaging can follow later.

### New Files to Create

#### `docker/entrypoint.sh`

Container entrypoint script that:
1. Runs as root
2. Installs build dependencies (passed via env var `BUILD_DEPS`)
3. Creates a `builduser` with the same UID/GID as the host user
4. Switches to `builduser`
5. Sources the build environment script
6. Executes the build commands

```
docker/entrypoint.sh
```

#### `docker/Dockerfile.bookworm`

```dockerfile
FROM debian:bookworm
RUN apt-get update && apt-get -y install \
    gawk grep git svn wget fakeroot bzip2 mercurial lsb-release jq xml2 \
    && apt-get clean
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

Similar Dockerfiles for `trixie`, `sid`, etc.

#### `docker/build-env.sh.template`

Template for the environment script that gets mounted into the container. Contains:
- All `B_*` variable exports
- All exported functions (`B_GET`, `B_LINKFILES`, `B_LINKFILE`, `B_UPDATEPKGBLD`, etc.)
- The BUILD section content from the recipe

### Changes to `build` Script

#### 1.1 New configuration items in `~/.buildrc`

```bash
# Build mode: "native" (default) or "docker"
BUILDMODE=docker

# Docker image names per distro (optional, overrides default mapping)
DOCKER_IMAGE_BOOKWORM=debian:bookworm
DOCKER_IMAGE_TRIXIE=debian:trixie

# Or use a custom prefix for pre-built images
DOCKER_IMAGE_PREFIX=

# Docker build directory (where Dockerfiles live)
DOCKER_DIR=$HOME/bin/build.git/docker
```

#### 1.2 New command-line flag: `--distro` / `-d`

```bash
build -b -d bookworm myrecipe
build -b -d trixie -a
```

This flag:
- Overrides auto-detected distribution
- Determines which Docker image to use in Docker mode
- Sets `distr` and `rel` variables for recipe section selection (`[BUILD BOOKWORM]`, `[REQUIRED BOOKWORM]`, etc.)

Add to `parse_options()`:

```bash
d)
   BUILDDISTRO="$OPTARG"
;;
```

#### 1.3 New function: `docker_image_select()`

Maps distro name to Docker image:

```bash
# Select docker image based on distro name
docker_image_select() {
   local distro="$1"
   local image

   # Check for custom image config first
   local config_var="DOCKER_IMAGE_$(echo "$distro" | tr '[:lower:]' '[:upper:]')"
   if [[ -n "${!config_var}" ]]; then
      image="${!config_var}"
   elif [[ -n "$DOCKER_IMAGE_PREFIX" ]]; then
      image="${DOCKER_IMAGE_PREFIX}${distro}"
   else
      # Default mapping
      case "$distro" in
         bookworm)  image="debian:bookworm" ;;
         trixie)    image="debian:trixie" ;;
         sid)       image="debian:sid" ;;
         *)         image="debian:$distro" ;;
      esac
   fi
   printf '%s' "$image"
}
```

#### 1.4 New function: `docker_run_build()`

Constructs and executes the `docker run` command:

```bash
# Run build phase inside a docker container
docker_run_build() {
   local image="$1"
   local build_section="$2"
   local container_id

   local docker_args=()

   # Remove container after run (unless debugging)
   [[ "$DEBUGSHELL" != "1" ]] && docker_args+=("--rm")

   # Hostname for identification
   docker_args+=("--hostname" "build-${B_NAME}")

   # Mount volumes (same paths inside and outside container)
   docker_args+=(
      "-v" "${RECIPEDIR}:${RECIPEDIR}"
      "-v" "${CACHEDIR}:${CACHEDIR}"
      "-v" "${DESTDIR}:${DESTDIR}"
      "-v" "${LOGDIR}:${LOGDIR}"
      "-v" "${HOME}/.buildrc:${HOME}/.buildrc:ro"
   )

   # Pass environment variables
   docker_args+=(
      "-e" "B_VERSION=${B_VERSION}"
      "-e" "B_INSTALLDIR=${B_INSTALLDIR}"
      "-e" "B_ARCH=${B_ARCH}"
      "-e" "B_NAME=${B_NAME}"
      "-e" "B_BUILDNR=${B_BUILDNR}"
      "-e" "B_CACHEDIR=${CACHEDIR}"
      "-e" "B_FILES=${B_FILES}"
      "-e" "B_FORCE=${B_FORCE}"
      "-e" "B_INSTANCE=${B_INSTANCE}"
      "-e" "HOME=${HOME}"
      "-e" "BUILDMODE=docker"
   )

   # Proxy settings
   [[ -n "$PROXY" ]] && docker_args+=("-e" "http_proxy=${PROXY}" "-e" "https_proxy=${PROXY}")

   # Build dependencies (passed to entrypoint for installation)
   docker_args+=("-e" "BUILD_DEPS=${BUILD_DEPS}")

   # Start container
   container_id=$(docker run -d "${docker_args[@]}" "$image" /entrypoint.sh bash -c "$build_section")

   # Follow logs
   docker logs -f "$container_id"
   local result=$?

   # Debug shell on failure
   if [[ $result -ne 0 && "$DEBUGSHELL" == "1" ]]; then
      printf '## Build failed. Container %s is still running.\n' "$container_id"
      printf '## Attach with: docker exec -it %s bash\n' "$container_id"
      printf '## Type exit to return.\n'
      docker exec -it "$container_id" bash
   fi

   return $result
}
```

#### 1.5 Modify `build()` function

Add Docker mode detection at the start of `build()`:

```bash
build() {
   B_NAME=$1
   B_VERSION=$2
   # ... (existing variable setup)

   if [[ "$BUILDMODE" == "docker" ]]; then
      # Get required packages section
      BUILD_DEPS=$( recipe_section_get "$B_NAME" "REQUIRED $distr $rel" opt )
      # ... (fall back logic as current)

      # Get build section
      local build_section
      build_section=$( recipe_section_get -q "$B_NAME" "BUILD $distr $rel" )
      # ... (fall back logic as current)

      # Select Docker image
      local image
      image=$( docker_image_select "$BUILDDISTRO" )

      # Run in container
      docker_run_build "$image" "$build_section"
      return $?
   fi

   # ... (existing native mode code continues unchanged)
}
```

#### 1.6 Modify `build_require()` for Docker mode

Inside the container, `build_require()` runs without `sudo` and detects the available package manager:

```bash
build_require() {
   local pkgs="$*"
   # ... (check if packages installed)

   # In Docker mode, no sudo needed
   if [[ "$BUILDMODE" == "docker" ]]; then
      if command -v apt-get > /dev/null 2>&1; then
         apt-get update > /dev/null 2>&1
         apt-get -y install "${toinst[@]}" > /dev/null 2>&1
      elif command -v dnf > /dev/null 2>&1; then
         dnf install -y "${toinst[@]}" > /dev/null 2>&1
      fi
      return 0
   fi

   # ... (existing native mode code with sudo)
}
```

#### 1.7 Modify `sanity_check()`

Add Docker-specific checks:

```bash
sanity_check() {
   # ... (existing checks)

   if [[ "$BUILDMODE" == "docker" ]]; then
      command -v docker > /dev/null 2>&1 || { output "Docker not found but BUILDMODE=docker."; exit 1; }
      docker info > /dev/null 2>&1 || { output "Docker daemon not running."; exit 1; }
   fi
}
```

#### 1.8 Handle `distr` and `rel` in Docker mode

When `--distro` is provided or `BUILDMODE=docker` is active, derive `distr` and `rel` from the specified distro rather than the host's `lsb_release`:

```bash
if [[ -n "$BUILDDISTRO" ]]; then
   distr=$(echo "$BUILDDISTRO" | cut -d- -f1 | tr '[:lower:]' '[:upper:]')
   rel=$(echo "$BUILDDISTRO" | cut -d- -f2- | tr '[:lower:]' '[:upper:]')
else
   distr=$(lsb_release -i -s | tr '[:lower:]' '[:upper:]')
   rel=$(lsb_release -c -s | tr '[:lower:]' '[:upper:]')
fi
```

#### 1.9 Handle the `B_GET` exported functions problem

Currently `B_GET` and other functions are defined inside `build()` and exported via `export -f`. Inside a Docker container, these functions don't exist. Solution:

**Option A (recommended):** Write the build environment to a script file and mount it:

```bash
# On host: write build env script
docker_prepare_env() {
   local envfile="$TMPDIR/build-env-${B_NAME}.sh"

   # Write all exported functions
   declare -f B_GET B_LINKFILES B_LINKFILE B_UPDATEPKGBLD >> "$envfile"

   # Write variable exports
   printf 'export B_VERSION=%s\n' "$B_VERSION" >> "$envfile"
   printf 'export B_INSTALLDIR=%s\n' "$B_INSTALLDIR" >> "$envfile"
   # ... etc

   printf '%s' "$envfile"
}
```

Then mount and source this file inside the container.

**Option B:** Include the function definitions in the `bash -c` command string. Risky for complex multi-line functions.

#### 1.10 Handle `$TMPDIR` inside container

In native mode, `TMPDIR` is on the host. In Docker mode, use the container's `/tmp` (which is tmpfs — fast and auto-cleaned):

```bash
docker_args+=("-e" "TMPDIR=/tmp")
```

No need to mount the host's `$TMPDIR` — the container's temp dir is ephemeral.

### Testing

- [ ] `BUILDMODE=native build -b -p build` — still works (regression test)
- [ ] `BUILDMODE=docker build -b -d bookworm build` — builds inside Debian 12 container
- [ ] `BUILDMODE=docker build -b -d trixie build` — builds inside Debian 13 container
- [ ] `BUILDMODE=docker build -b -d bookworm -s build` — drops to shell on failure
- [ ] Built `.deb` appears in `$PKGDIR` on host with correct ownership
- [ ] Cache directory is shared and reused across builds
- [ ] `B_GET http/git/svn/hg` work inside container
- [ ] Build logs appear in `$LOGDIR` on host
- [ ] File permissions on built artifacts match host user (not root)

---

## Phase 2: Docker Packaging Phase

**Goal:** Run the packaging phase (`-p` flag) inside the Docker container too. Currently, packaging happens on the host after the build phase. This requires the host to have `dpkg`, `fakeroot`, etc. In Docker mode, packaging should happen inside the same container that just built the software.

**Why separate from Phase 1:** Packaging is more complex — it requires the container to have `dpkg`/`fakeroot` installed, handle DEB section parsing, and write the final `.deb` to the mounted `$PKGDIR`. Getting the build phase working first validates the Docker infrastructure; packaging builds on that.

### Changes

#### 2.1 Keep the container alive between build and package

Currently, build and package are separate loops in `main()`. For Docker mode, the container from the build phase must persist so the package phase can use it. Options:

**Option A (recommended):** Run build AND package in a single container invocation:

```bash
# In Docker mode, combine build + package into one container run
docker_run_build_and_package() {
   local image="$1"
   local combined_cmd="$2"

   # ... (same docker run setup)

   # Combined command does build, then package
   docker run --rm "${docker_args[@]}" "$image" bash -c "$combined_cmd"
}
```

The combined command would be:

```bash
# 1. Run BUILD section
# 2. Run packaging function
# 3. Copy result to $PKGDIR
```

**Option B:** Keep container running, use `docker exec` for subsequent phases. More complex, but allows the host to inspect between phases.

#### 2.2 Modify `main()` for Docker mode

In Docker mode, the check → build → package → repo flow changes:

```bash
if [[ "$BUILDMODE" == "docker" ]]; then
   # Check versions on host (lightweight, no container needed)
   for i in "${!work_recipes[@]}"; do
      work_version[$i]=$( check_version_built "${work_recipes[$i]}" )
      work_built[$i]=$?
   done

   # Build + Package in container (combined)
   for i in "${!work_recipes[@]}"; do
      if (( work_built[$i] == 0 )) || (( B_FORCE == 1 )); then
         docker_run_build_and_package "$image" "$combined_cmd"
         # ... handle result
      fi
   done

   # To repo on host (or in container)
   # ... (same as current)
else
   # ... (existing native mode flow)
fi
```

#### 2.3 Package build dependencies in the container

Add `fakeroot` and `dpkg-dev` to the Docker image (or install them in the entrypoint). These are needed for `package_deb()`.

#### 2.4 Handle `PKGLIST` access from container

`PKGLIST` is read and written by `package_buildnr_get()` and `B_UPDATEPKGBLD()`. It must be accessible inside the container via the mounted `$RECIPEDIR` volume (since `PKGLIST=$RECIPEDIR/pkglist`).

This already works because `$RECIPEDIR` is mounted. No change needed.

### Testing

- [ ] `BUILDMODE=docker build -b -p -d bookworm build` — builds AND packages in one container
- [ ] Resulting `.deb` is valid: `dpkg-deb --info` shows correct metadata
- [ ] `PKGLIST` is updated correctly on host after container exits
- [ ] Package version numbers are correct
- [ ] `[DEB]` section substitutions (`B_VERSION`, `B_ARCH`, `B_PF`) work inside container
- [ ] `B_DEBIAN/DEBIAN` files (postinst etc.) are included in package

---

## Phase 3: RPM Package Support

**Goal:** Implement `package_rpm()` and all supporting infrastructure so that RPM packages can be built inside Docker containers running CentOS/Fedora/RHEL images.

**Why this phase:** This directly addresses the MULTI.md open items. Docker makes it possible (no separate Red Hat machine needed), but the packaging code must be written.

**Prerequisite:** Phase 1 must be complete (Docker build infrastructure working).

### New Files to Create

#### `docker/Dockerfile.centos9`

```dockerfile
FROM centos:9
RUN dnf install -y \
    gawk grep git svn wget bzip2 mercurial jq rpm-build redhat-rpm-config \
    && dnf clean all
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

Similar Dockerfiles for Fedora, Rocky Linux, etc.

### Changes to `build` Script

#### 3.1 Implement `package_rpm()`

Replace the current stub with a real implementation. The function should:

1. Read the `[RPM]` section from the recipe (like `[DEB]` is read for Debian)
2. Generate a `.spec` file from the recipe section
3. Set up the RPM build directory structure (`SPECS/`, `BUILD/`, `RPMS/`, `SRPMS/`)
4. Run `rpmbuild -bb` to build the binary RPM
5. Copy the resulting `.rpm` to `$PKGDIR`

```bash
package_rpm() {
   local pkg="$1"
   local version="$2"

   local pkgready
   pkgready=$( recipe_item_get "$pkg" PKG pkgready )

   if [[ -z "$pkgready" ]]; then
      local P_PKGNAME="${pkg}_${ID}_${B_ARCH}"
      local P_BUILDNR
      P_BUILDNR=$( package_buildnr_get "${P_PKGNAME}" )

      # Read [RPM] section from recipe
      local INFO
      INFO=$( recipe_section_get "$pkg" RPM ) || return 1

      # Apply substitutions
      local pkgversion="${version//\-/}-${P_BUILDNR}"
      INFO="${INFO//B_VERSION/$pkgversion}"
      INFO="${INFO//B_ARCH/$B_ARCH}"
      [[ -n "$PKGPOSTFIX" ]] && INFO="${INFO//B_PF/$PKGPOSTFIX}"

      # Create spec file
      local TMP
      TMP=$( mktemp -p "$TMPDIR" -d )
      mkdir -p "$TMP"/SPECS "$TMP"/BUILD "$TMP"/RPMS "$TMP"/SRPMS

      printf '%s\n' "$INFO" > "$TMP"/SPECS/"${pkg}.spec"

      # Copy build output to BUILD root
      local pkgdir
      if [[ -n "$DESTSPLIT" ]]; then
         pkgdir="$DESTDIR/$B_ARCH/$pkg/$version"
      else
         pkgdir="$DESTDIR/$B_ARCH/$pkg-$version"
      fi
      tar -C "$pkgdir" -cf - . | tar -C "$TMP"/BUILD -xf -

      # Build RPM
      rpmbuild -bb --buildroot "$TMP"/BUILD \
         --define "_topdir $TMP" \
         "$TMP"/SPECS/"${pkg}.spec"

      # Copy result
      cp "$TMP"/RPMS/*/"${pkg}"*.rpm "$PKGDIR"/

      # Update PKGLIST
      grep "^${P_PKGNAME}_${B_ARCH}" "$PKGLIST" > /dev/null && \
         sed -i "/^${P_PKGNAME}_${B_ARCH}/d" "$PKGLIST"
      printf '%s\t%s\n' "${P_PKGNAME}_${B_ARCH}" "$P_BUILDNR" >> "$PKGLIST"

      rm -rf "$TMP"
   else
      # pkgready mode
      cp "$pkgdir"/*.rpm "$PKGDIR"
   fi
}
```

**Note:** This is a starting implementation. RPM spec files have different conventions than Debian control files. The `[RPM]` section format needs to be designed. See task 3.3.

#### 3.2 Modify `package()` routing for Docker mode

Currently `package()` checks `$OS` to route to `package_deb()` or `package_rpm()`. In Docker mode, the container IS the target distro, so check for the available package tool instead:

```bash
package() {
   # ... (existing setup)

   local type
   type=$( recipe_item_get "$pkg" PKG type )

   for pkgtype in ${type/,/ }; do
      case $pkgtype in
         "deb")
            if [[ "$BUILDMODE" == "docker" ]] || [[ "$OS" == "Debian GNU/Linux" ]]; then
               package_deb "$pkg" "$version" "$ID"
               return $?
            fi
            ;;
         "rpm")
            if [[ "$BUILDMODE" == "docker" ]] || [[ "$OS" == "CentOS Linux" ]]; then
               package_rpm "$pkg" "$version" "$ID"
               return $?
            fi
            ;;
         *)
            ERR=1 output "Unknown package type ($pkgtype)."
            return 1
            ;;
      esac
   done
}
```

#### 3.3 Design the `[RPM]` recipe section format

The test recipe already has an `[RPM]` section:

```
[RPM]
Summary: Test package
Name: testpkg
Version: B_VERSION
Release: B_BUILDNR
BuildRoot: /var/tmp/%{name}-buildroot
```

This needs to be documented and potentially expanded. Key considerations:

- The `Version:` field uses `B_VERSION` substitution (same as DEB)
- The `Release:` field uses `B_BUILDNR` substitution
- RPM spec files need `%description`, `%files`, `%install` sections
- Should the recipe's `[RPM]` section contain the full spec, or just metadata with `%files` etc. auto-generated from the build output?

**Recommendation:** Start with a simple approach — the `[RPM]` section contains a complete `.spec` file body, similar to how `[DEB]` contains the control file. Auto-generation of `%files` can be added later.

#### 3.4 Implement `build_require()` for RPM-based containers

Inside a CentOS/Fedora container, replace `dpkg-query` with `rpm` for checking installed packages:

```bash
build_require() {
   local pkgs="$*"

   if [[ "$BUILDMODE" == "docker" ]]; then
      # Detect package manager inside container
      if command -v dnf > /dev/null 2>&1; then
         dnf install -y $pkgs
         return $?
      elif command -v apt-get > /dev/null 2>&1; then
         apt-get update > /dev/null 2>&1
         apt-get -y install $pkgs > /dev/null 2>&1
         return $?
      fi
   fi

   # ... (existing native mode code)
}
```

#### 3.5 Modify `require_software()` for Docker mode

In Docker mode, `require_software()` should check for tools inside the container or assume they're in the Docker image:

```bash
require_software() {
   if [[ "$BUILDMODE" == "docker" ]]; then
      # Tools are provided by the Docker image or installed by build_require
      # Skip host-side check
      return
   fi
   # ... (existing native mode code)
}
```

#### 3.6 Add RPM support to `package_torepo()`

```bash
package_torepo() {
   # ... (existing setup)

   for type in "${!splittype[@]}"; do
      case "$type" in
         "deb")
            $TODEBREPO "${splittype[$type]}"
            # ...
         ;;
         "rpm")
            $TORPMREPO "${splittype[$type]}"
            # ...
         ;;
      esac
   done
}
```

#### 3.7 Add `TORPMREPO` configuration

New config variable in `~/.buildrc`:

```bash
# Script to use to publish RPM packages to repository
TORPMREPO="torepo-rpm"
```

#### 3.8 Create `torepo-rpm` script (or extend `torepo`)

A script similar to `torepo` but for RPM repos, using `createrepo_c` on the destination server.

#### 3.9 Update test recipe

Add an RPM build section to the test recipe:

```
[BUILD CENTOS 9]
mkdir -p $B_INSTALLDIR/opt/test/bin
cp $B_FILES/test.sh $B_INSTALLDIR/opt/test/bin

[RPM]
Summary: Test package
Name: testpkg
Version: B_VERSION
Release: B_BUILDNR
License: GPL-3.0
Group: Development/Tools
%description
Test package for build script
%files
/opt/test/bin/test.sh
```

### Testing

- [ ] `build -b -p -d bookworm test` — still produces valid `.deb`
- [ ] `build -b -p -d centos9 test` — produces valid `.rpm`
- [ ] `rpm -qpi` on the resulting RPM shows correct metadata
- [ ] `rpm -K` on the resulting RPM passes signature/digest check
- [ ] `[RPM]` section substitutions (`B_VERSION`, `B_ARCH`, `B_PF`) work
- [ ] `build_require()` installs packages via `dnf` inside CentOS container
- [ ] `PKGLIST` is updated correctly after RPM build
- [ ] RPM packages can be pushed to a repo via `torepo-rpm`

---

## Phase 4: Interactive Development Mode

**Goal:** Add a `--shell` mode that starts a Docker container matching a specific distribution and drops the user into an interactive shell with all build environment variables and directories set up. This replaces the current need for persistent containers per distro.

**Why this phase:** This is what enables the recipe development workflow in Docker mode. It's essential for daily use but depends on Phase 1 infrastructure being in place.

### Changes

#### 4.1 New command-line flag: `--shell`

```bash
build --shell bookworm          # Shell in Debian 12 container
build --shell trixie            # Shell in Debian 13 container
build --shell centos9           # Shell in CentOS 9 container
build --shell bookworm -i test  # Shell with instance context
```

Add to `parse_options()`:

```bash
S)
   SHELL_MODE=1
   BUILDDISTRO="$OPTARG"
;;
```

#### 4.2 Implement `docker_shell()`

```bash
# Start interactive development shell in a Docker container
docker_shell() {
   local distro="$1"
   local image
   image=$( docker_image_select "$distro" )

   local docker_args=(
      "-it"
      "--hostname" "build-dev-${distro}"
   )

   # Mount volumes
   docker_args+=(
      "-v" "${RECIPEDIR}:${RECIPEDIR}"
      "-v" "${CACHEDIR}:${CACHEDIR}"
      "-v" "${DESTDIR}:${DESTDIR}"
      "-v" "${PKGDIR}:${PKGDIR}"
      "-v" "${LOGDIR}:${LOGDIR}"
      "-v" "${HOME}/.buildrc:${HOME}/.buildrc:ro"
      "-v" "$(dirname "$(command -v build)")/build:${HOME}/bin/build:ro"
   )

   # Environment
   docker_args+=(
      "-e" "HOME=${HOME}"
      "-e" "B_ARCH=${B_SARCH}"
      "-e" "BUILDMODE=docker"
   )

   [[ -n "$PROXY" ]] && docker_args+=("-e" "http_proxy=${PROXY}" "-e" "https_proxy=${PROXY}")

   printf '## Build development shell for %s\n' "$distro"
   printf '## Type exit to leave.\n'

   docker run "${docker_args[@]}" "$image" bash
}
```

#### 4.3 Handle the `-s` debug shell in Docker mode

When a build fails with `-s` flag in Docker mode:

```bash
# Instead of starting a bash shell in the temp dir on the host,
# exec into the running container
if [[ $result -ne 0 && -n "$DEBUGSHELL" ]]; then
   printf '## Build failed. Container %s is still running.\n' "$container_id"
   printf '## Attach with: docker exec -it %s bash\n' "$container_id"
   docker exec -it "$container_id" bash
fi
```

#### 4.4 Add `build --attach` convenience command

For when a user has left a debug session but the container is still running:

```bash
build --attach <container-id>
# Equivalent to: docker exec -it <container-id> bash
```

### Testing

- [ ] `build --shell bookworm` — starts interactive shell in Debian 12 container
- [ ] Inside shell: `apt-get install <pkg>` works
- [ ] Inside shell: `build -b myrecipe` works (build inside the dev container)
- [ ] Inside shell: recipe files, cache, build dir are accessible
- [ ] Files created inside shell are owned by host user (not root)
- [ ] `exit` cleanly removes the container
- [ ] `build -b -s -d bookworm test` — on failure, drops into container shell
- [ ] `build --attach <id>` — re-attaches to a kept container

---

## Phase 5: Docker Image Management

**Goal:** Automate Docker image building, updating, and caching so users don't need to manually manage images.

### Changes

#### 5.1 Auto-build images on first use

```bash
docker_image_ensure() {
   local distro="$1"
   local image
   image=$( docker_image_select "$distro" )

   # Check if image exists locally
   if ! docker image inspect "$image" > /dev/null 2>&1; then
      output "Docker image $image not found. Pulling..."
      docker pull "$image" || {
         # Try building from local Dockerfile
         local dockerfile="${DOCKER_DIR}/Dockerfile.${distro}"
         if [[ -f "$dockerfile" ]]; then
            output "Building image from $dockerfile..."
            docker build -t "$image" -f "$dockerfile" "$DOCKER_DIR"
         else
            ERR=1 output "Cannot find or build Docker image for $distro."
            return 1
         fi
      }
   fi
}
```

#### 5.2 Image refresh command

```bash
build --update-images
# Pulls latest base images and rebuilds custom images
```

#### 5.3 Image age checking

Optionally warn or auto-rebuild when images are older than a configurable threshold:

```bash
# In ~/.buildrc
DOCKER_IMAGE_MAX_AGE=7  # days
```

### Testing

- [ ] Fresh system with no images: `build -b -d bookworm test` auto-pulls image
- [ ] Custom Dockerfile images are built automatically
- [ ] `build --update-images` refreshes all configured images
- [ ] Stale image warning works

---

## Phase 6: Cross-Architecture Support (ARM)

**Goal:** Enable building packages for ARM architectures (arm64, armhf) using QEMU emulation or cross-compilation.

**Why last:** This is a nice-to-have that depends on all Docker infrastructure being stable. Performance limitations mean it's only practical for certain types of packages.

### Changes

#### 6.1 New command-line flag: `--platform`

```bash
build -b -p -d bookworm --platform arm64 myrecipe
build -b -p -d bookworm --platform armhf myrecipe
```

Add to `parse_options()`:

```bash
P)
   BUILDTARGET="$OPTARG"
;;
```

#### 6.2 Register QEMU binfmt handlers

Add a `build --setup-qemu` command:

```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

Or check and auto-register on first use of a foreign platform.

#### 6.3 Pass `--platform` to Docker

```bash
docker_args+=("--platform" "linux/${BUILDTARGET}")
```

#### 6.4 Update `arch_get()` for Docker mode

When `--platform` is specified, override the auto-detected architecture:

```bash
arch_get() {
   if [[ -n "$BUILDTARGET" ]]; then
      case "$BUILDTARGET" in
         arm64) printf 'arm64' ;;
         armhf) printf 'armhf' ;;
         amd64) printf 'amd64' ;;
         *)     printf '%s' "$BUILDTARGET" ;;
      esac
      return
   fi
   # ... (existing auto-detection)
}
```

#### 6.5 Cross-compilation support (future)

Add support for cross-compilation toolchains as an alternative to QEMU emulation. This would require:
- Installing cross-compilers in the Docker image
- Setting `CC`, `CXX`, `PKG_CONFIG_PATH`, etc. in the build environment
- Recipe-level opt-in via `[INFO]` section (e.g., `crosscompile=y`)

This is documented here for awareness but can be deferred beyond Phase 6.

### Testing

- [ ] `build --setup-qemu` registers binfmt handlers
- [ ] `build -b -d bookworm --platform arm64 test` — builds ARM64 package
- [ ] `build -b -d bookworm --platform armhf test` — builds ARMhf package
- [ ] Resulting `.deb` has correct architecture in filename
- [ ] `dpkg-deb -I` shows correct `Architecture:` field
- [ ] Document expected performance: arch-independent packages near-native speed, compilation 5-15x slower

---

## Phase 7: Advanced Features

**Goal:** Add capabilities that Docker uniquely enables or simplifies.

### 7.1 Parallel builds

Multiple recipes can be built simultaneously in separate containers:

```bash
build -b -a -j4  # Build 4 recipes at once
```

Implementation: background the `docker_run_build` calls and wait for all to complete.

### 7.2 Container reuse for same recipe

When running `build -b -p -r`, the build → package → repo flow currently runs in separate loops. In Docker mode, a single container can handle all phases:

```bash
build -b -p -r -d bookworm myrecipe  # Single container for all phases
```

### 7.3 Build caching

Skip rebuild if:
- Base image hasn't changed
- Recipe hasn't changed
- Build output already exists

Requires hashing the recipe content and base image ID.

### 7.4 CI/CD integration

Document how to use the build script in CI/CD pipelines (GitHub Actions, GitLab CI) with Docker mode. The script is already Docker-native, so this should be straightforward.

### 7.5 Consolidate `clean` and `debclean`

As identified in `improvement.md`, merge `clean` and `debclean` into a single script. In Docker mode, these are less relevant but still useful for `BUILDMODE=native`.

---

## Dependency Graph

```
Phase 0: Bash cleanup
    │
    ▼
Phase 1: Docker build phase ──────► Phase 4: Interactive shell mode
    │                                    │
    ▼                                    ▼
Phase 2: Docker packaging phase     (usable independently)
    │
    ▼
Phase 3: RPM package support
    │
    ▼
Phase 5: Docker image management
    │
    ▼
Phase 6: Cross-architecture (ARM)
    │
    ▼
Phase 7: Advanced features
```

- Phase 0 must come first (everything builds on clean code)
- Phase 1 must come before Phase 2 and 3 (Docker infrastructure must work first)
- Phase 4 can be done in parallel with Phase 2 (both depend on Phase 1 only)
- Phase 3 depends on Phase 2 (RPM packaging needs the Docker packaging flow)
- Phases 5, 6, 7 are sequential enhancements

---

## Summary: What Each Phase Delivers

| Phase | What You Get | Effort Estimate |
|-------|-------------|-----------------|
| **0** | Clean, shellcheck-passing, bash-skill-compliant codebase | Medium (many small changes) |
| **1** | Docker builds for Debian 12/13 from a single machine | Medium (core infrastructure) |
| **2** | Docker packaging — complete build+package in container | Small (builds on Phase 1) |
| **3** | RPM package building via Docker | Medium (new `package_rpm()` implementation) |
| **4** | `build --shell` for interactive recipe development | Small (wrapper around `docker run`) |
| **5** | Automatic Docker image management | Small |
| **6** | ARM/Raspberry Pi builds via QEMU | Small (mostly config, documented limitations) |
| **7** | Parallel builds, caching, CI/CD | Medium-Large |

After **Phase 2**, you have a fully functional Docker-based build system that replaces the need for separate machines per distro. After **Phase 3**, you can also build RPM packages. Everything after that is incremental improvement.