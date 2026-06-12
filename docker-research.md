# Docker Integration Research for Build

## 1. Executive Summary

**Yes, it is absolutely feasible** to restructure the build script to use Docker containers as temporary build environments. This would allow a single machine to build packages for Debian 12, Debian 13, and other distributions without needing separate VMs or containers running 24/7. The build script would orchestrate Docker containers that are created on demand and removed after building.

**Cross-architecture builds (e.g., Raspberry Pi/ARM) are possible via QEMU emulation, but with significant performance trade-offs.** They are viable for lightweight packages but impractical for anything compilation-heavy.

The interactive development workflow (getting a shell, installing packages, designing recipes) can be fully preserved with Docker.

---

## 2. How It Would Work

### 2.1 Current Flow

```
build script → runs directly on host → installs/removes packages via apt-get
             → builds in $TMPDIR on host filesystem
             → packages with fakeroot dpkg-deb on host
             → outputs .deb to $PKGDIR on host
```

### 2.2 Proposed Docker Flow

```
build script (on host) → starts Docker container from appropriate base image
                        → mounts recipes, cache, and output directories into container
                        → runs build phase inside container
                        → optionally drops to shell inside container on failure (-s flag)
                        → copies built .deb files out
                        → removes container
```

The key insight: the **orchestration logic stays on the host**, but the **actual build and package creation happens inside a container**.

### 2.3 Container Lifecycle

For each recipe build:

1. **Pull/select base image** — e.g., `debian:bookworm` for Debian 12, `debian:trixie` for Debian 13
2. **Start container** with appropriate volumes mounted
3. **Install build dependencies** inside container (no sudo needed — container runs as root by default)
4. **Execute BUILD section** inside container
5. **Package** inside container (fakeroot/dpkg available)
6. **Copy result** to host's `$PKGDIR`
7. **Destroy container** (or keep for debugging)

---

## 3. Cross-Architecture Builds (ARM / Raspberry Pi)

### 3.1 How It Works

Docker supports running foreign-architecture containers on x86 hosts through **QEMU user-mode emulation** via the `binfmt_misc` kernel feature. When set up:

```bash
# One-time setup on the host
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Then run ARM containers transparently
docker run --rm --platform linux/arm64 debian:bookworm uname -m
# Output: aarch64

docker run --rm --platform linux/armhf debian:bookworm uname -m  
# Output: armv7l
```

The `--platform` flag tells Docker which architecture to use. With QEMU registered, the kernel automatically intercepts foreign binaries and routes them through the emulator.

### 3.2 Performance

This is the critical limitation:

| Scenario | Relative Speed |
|----------|----------------|
| Native x86 on x86 host | 1× (baseline) |
| Same-arch Docker on x86 host | ~0.95–1× (near native) |
| ARM64 via QEMU on x86 host | **2–10× slower** |
| ARMhf via QEMU on x86 host | **5–15× slower** |

The performance penalty comes from QEMU translating every instruction. For the types of packages this build system creates (mostly downloading, configuring, and packaging pre-built software), this could be acceptable. For compilation-heavy builds (C/C++ projects, Rust, Go), it becomes impractical.

### 3.3 What Works and What Doesn't

| Aspect | Works? | Notes |
|--------|--------|-------|
| `B_GET http` | ✅ | Network access works in containers |
| `B_GET git/svn/hg` | ✅ | VCS tools installable in container |
| `B_GET go` | ✅ | Go works under emulation (slowly) |
| `dpkg-deb` / `fakeroot` | ✅ | Full Debian toolchain available |
| Native ARM compilation | ⚠️ | Works but 5–15× slower than native |
| Cross-compilation (faster) | ⚠️ | Possible but requires different approach (see 3.4) |
| Kernel modules / device access | ❌ | Containers share host kernel |

### 3.4 Alternative: Cross-Compilation Instead of Emulation

For compilation-heavy ARM packages, cross-compilation is far more efficient:

```bash
# On x86 host, install cross-compiler
apt install gcc-aarch64-linux-gnu

# Build with cross-compiler instead of emulated native compiler
aarch64-linux-gnu-gcc -o binary source.c
```

However, cross-compilation requires recipe changes (setting `CC`, `PKG_CONFIG_PATH`, etc.) and doesn't work for everything (e.g., Python wheels with native extensions, Go CGO with C libraries). The build system would need a `[BUILD arm64]` section or similar in recipes.

**Recommendation:** Support both approaches. Use QEMU emulation for simple/arch-independent packages, and cross-compilation for heavy builds. This can be a future enhancement.

---

## 4. Interactive Development Workflow

### 4.1 Current Workflow

Currently you can:
- SSH into a Debian 12 or 13 container
- Install packages with `apt-get`
- Manually run build commands to develop a recipe
- Use `build -s` to drop into a shell on build failure

### 4.2 Docker Equivalent

This workflow maps directly to Docker:

```bash
# Start a persistent container for recipe development
docker run -dit \
   --name build-dev-bookworm \
   -v ~/recipes:/home/builduser/recipes \
   -v ~/cache:/home/builduser/cache \
   -v ~/build:/home/builduser/build \
   -v ~/packages:/home/builduser/packages \
   -v ~/log:/home/builduser/log \
   -v /path/to/build.git:/home/builduser/bin/build.git \
   debian:bookworm bash

# Get a shell in the container
docker exec -it build-dev-bookworm bash

# Inside: install packages, develop recipe, etc.
apt-get update && apt-get install <whatever>
build -b -p my-new-recipe

# When done, remove the container
docker rm -f build-dev-bookworm
```

### 4.3 The `-s` (Debug Shell) Flag

Currently `build -s` drops to a shell in the build environment when a build fails. With Docker, this would become:

```bash
# Instead of destroying the container on failure, keep it running
# and attach to it with a shell
docker exec -it <container-id> bash
```

The implementation would:
1. On build failure, **not** remove the container
2. Print the container ID so the user can attach
3. Optionally provide a `build --attach <id>` convenience command

### 4.4 Proposed New Flag: `build --shell` or `build -i --shell`

For recipe development, a new mode could start a container matching a specific distribution and drop the user into it:

```bash
# Start interactive shell in a Debian bookworm container
build --shell bookworm

# With an instance name
build --shell bookworm -i my-instance
```

This would:
1. Start a container from the specified base image
2. Mount all the usual directories
3. Set up all the `B_*` environment variables
4. Source `~/.buildrc` (or a container-specific config)
5. Drop the user into a bash shell

---

## 5. What Needs to Change in the Build Script

### 5.1 Configuration Changes (`~/.buildrc`)

New configuration items needed:

```bash
# Docker mode: "docker" or "native" (default: native for backward compat)
BUILDMODE=docker

# Base images per distribution/release
DOCKER_IMAGES="debian:bookworm debian:trixie"

# Or more specifically:
DOCKER_IMAGE_DEBIAN_BOOKWORM=debian:bookworm
DOCKER_IMAGE_DEBIAN_TRIXIE=debian:trixie
DOCKER_IMAGE_DEBIAN_SID=debian:sid

# Optional: custom Dockerfile path for pre-built images with common build tools
DOCKER_IMAGE_PREFIX=myregistry/build-

# Optional: keep container after build for debugging (default: no)
DOCKER_KEEP=no

# Docker build user (to avoid running everything as root)
DOCKER_USER=builduser
```

### 5.2 Script Changes — Overview

The changes can be **incremental**. The native mode continues to work exactly as before. Docker mode is activated via the `BUILDMODE` config variable.

#### Phase 1: Docker Wrapper (Minimal Change)

The simplest approach: the build script on the **host** remains the orchestrator. Only the build step runs inside Docker.

```
build (host) ─→ detect BUILDMODE=docker
              ─→ select base image based on distro/release
              ─→ docker run -v ... -e ... <image> bash -c "<build commands>"
              ─→ collect results from mounted volumes
```

**What stays on the host:**
- `main()`, `parse_options()`, `version_get()` (version checks typically don't need a specific distro)
- `sanity_check()`, `output()`, `lock_get()`
- Recipe file reading and section parsing

**What moves into the container:**
- `build()` — the actual build phase
- `build_require()` / `build_require_remove()` — package install/remove
- `package_deb()` — packaging (needs `dpkg`, `fakeroot` of the target distro)
- All `B_GET`, `B_LINKFILES`, etc. functions

#### Phase 2: Distribution Detection Changes

Currently the script detects the host OS to determine which `[REQUIRED ...]` and `[BUILD ...]` sections to use:

```bash
distr=$(lsb_release -i -s | tr '[:lower:]' '[:upper:]')
rel=$(lsb_release -c -s | tr '[:lower:]' '[:upper:]')
```

In Docker mode, this needs to reflect the **target** distribution, not the host. Options:

1. **Configuration-driven:** The user specifies which distro to build for in `.buildrc` or via a new command-line flag
2. **Image-driven:** Derive `distr` and `rel` from the Docker base image name/contents

Recommended: A new `-d` / `--distro` flag:

```bash
build -b -p -d bookworm myrecipe    # Build for Debian bookworm
build -b -p -d trixie myrecipe      # Build for Debian trixie
```

This would override the auto-detected distribution and select the appropriate Docker image.

#### Phase 5: `require_software()` Changes

Currently checks for host tools. In Docker mode, these tools would be pre-installed in the build image or installed on-the-fly inside the container. The `require_software()` function should either:
- Be skipped in Docker mode (tools are in the image), or
- Check inside the container

#### Phase 6: `build()` Function Changes

The `build()` function needs the most significant restructuring. In Docker mode:

```bash
build() {
   # ... (version resolution stays on host)
   
   # Construct docker run command
   local docker_cmd="docker run --rm"
   
   # Keep container on failure for -s flag
   test "$DEBUGSHELL" = "1" && docker_cmd="docker run"
   
   # Mount directories
   docker_cmd+=" -v $RECIPEDIR:$RECIPEDIR"
   docker_cmd+=" -v $CACHEDIR:$CACHEDIR"
   docker_cmd+=" -v $DESTDIR:$DESTDIR"
   docker_cmd+=" -v $PKGDIR:$PKGDIR"
   docker_cmd+=" -v $LOGDIR:$LOGDIR"
   
   # Pass environment variables
   docker_cmd+=" -e B_VERSION=$B_VERSION"
   docker_cmd+=" -e B_INSTALLDIR=$B_INSTALLDIR"
   docker_cmd+=" -e B_ARCH=$B_ARCH"
   # ... etc
   
   # Select image
   local image="debian:${rel_lower}"
   
   # Run build inside container
   docker_cmd+=" $image bash -c '<build section from recipe>'"
   
   eval "$docker_cmd"
}
```

Actually, since recipes can contain complex multi-line shell code, a better approach is to mount the recipe files and execute them:

```bash
docker_cmd+=" $image bash -c 'source /build-env.sh; bash -e /tmp/build-section.sh'"
```

Where `/build-env.sh` contains all the exported functions and variables, and `/tmp/build-section.sh` contains the recipe's BUILD section.

#### Phase 7: `build_require()` Changes

In Docker mode, `build_require()` runs **inside** the container. Since the container is root by default, `sudo` isn't needed:

```bash
# Inside container (no sudo needed)
apt-get update > /dev/null 2>&1
apt-get -qq -y install "${toinst[@]}" > /dev/null 2>&1
```

This is actually simpler — no sudo, no permission issues. The container starts clean each time, so `build_require_remove()` becomes unnecessary (just destroy the container).

### 5.3 Docker Base Images

You would need Docker images for each target platform. Two approaches:

**Approach A: Minimal base images (recommended to start)**

Use official Debian images directly. Build dependencies are installed on each run:

```bash
docker run --rm debian:bookworm bash -c "apt-get update && apt-get -y install <deps> && <build>"
```

- Pros: Always up-to-date, simple, no image maintenance
- Cons: Slightly slower (installs deps each time), requires network

**Approach B: Pre-built images with common tools**

Create custom images with common build tools pre-installed:

```dockerfile
# Dockerfile.build-bookworm
FROM debian:bookworm
RUN apt-get update && apt-get -y install \
    gawk grep git svn wget fakeroot bzip2 hg lsb-release jq xml2 \
    && apt-get clean
```

- Pros: Faster builds (deps already installed), reproducible
- Cons: Need to maintain images, periodic updates

**Approach C: Build image on first use (hybrid)**

The build script creates the Docker image the first time it's needed for a distro, and rebuilds it periodically (e.g., weekly):

```bash
# In build script
if ! docker image inspect "build-$distro:$tag" > /dev/null 2>&1; then
   docker build -t "build-$distro:$tag" -f Dockerfile."$distro" .
fi
```

### 5.4 Volume Mounting Strategy

The host directories need to be carefully mapped into the container:

| Host Path | Container Path | Mode | Purpose |
|-----------|---------------|------|---------|
| `$RECIPEDIR` | Same path | rw | Recipe files and .files directories |
| `$CACHEDIR` | Same path | rw | Download cache (shared across builds) |
| `$DESTDIR` | Same path | rw | Build output directory |
| `$PKGDIR` | Same path | rw | Final package output |
| `$LOGDIR` | Same path | rw | Build logs |
| `$TMPDIR` | Container `/tmp` | — | Use container's tmpfs for speed |
| `~/.buildrc` | Same path | ro | Configuration |

Using the **same paths** inside and outside the container is strongly recommended. This avoids path translation issues in recipes (which often reference absolute paths like `$B_INSTALLDIR`).

**Important:** The container user's UID/GID should match the host user to avoid file permission issues. Use Docker's `--user` flag or create a matching user in the image:

```bash
docker run --rm --user "$(id -u):$(id -g)" ...
```

Or use the `devshell` pattern (see research) where the image creates a user matching the mounted volume's ownership.

### 5.5 File Permission Handling

This is a common Docker pain point. If the container runs as root, all created files will be owned by root on the host — requiring `sudo` to clean up. Solutions:

1. **Run as host user:** `docker run --user "$(id -u):$(id -g)"` — simplest, but some packages need root for `apt-get install`
2. **Start as root, switch user after install:** Use a container entrypoint script
3. **Use `fakeroot` for packaging only:** Already done for `dpkg --build`

Recommended approach: Start container as root (for dependency installation), then `su` to the build user for the actual build and packaging steps. The entrypoint script handles this:

```bash
#!/bin/bash
# /entrypoint.sh — container entrypoint
if [ "$(id -u)" = "0" ]; then
    # Install dependencies (passed as env var or script arg)
    if [ -n "$BUILD_DEPS" ]; then
        apt-get update
        apt-get -y install $BUILD_DEPS
    fi
    # Switch to build user
    exec su - builduser -c "$*"
else
    exec "$@"
fi
```

---

## 6. What No Longer Works (or Works Differently)

### 6.1 Works Differently

| Feature | Native Mode | Docker Mode |
|---------|------------|-------------|
| Dependency install | `sudo apt-get` on host | `apt-get` inside container (no sudo needed) |
| Dependency removal | `build_require_remove()` | Not needed — container is destroyed |
| Build isolation | Shared host environment | Full isolation per build |
| `-s` debug shell | Shell on host in build dir | Shell inside container (need `docker exec`) |
| OS detection | Auto from `/etc/os-release` | Target distro from config or flag |
| `clean`/`debclean` | Reverts host packages | **Not applicable** — container is always clean |
| `postbuild` script | Runs on host | Could run inside or outside container |

### 6.2 No Longer Needed

- **`clean` and `debclean` scripts** — In Docker mode, each build starts from a clean base image. There's no host system pollution to clean up. These scripts remain useful for `BUILDMODE=native` but become unnecessary for Docker builds.
- **`build_require_remove()`** — Same reason. The container is ephemeral.
- **`INSTDEP` / `DEINSTDEP` config** — Dependencies are always installed inside the container; there's no host impact.
- **Lock file** — Docker containers are naturally isolated. The `/tmp/build.lck` lock mechanism is only needed when two builds might share a host environment. With Docker, you can run multiple containers concurrently.

### 6.3 Things That Break or Need Workarounds

| Issue | Impact | Workaround |
|-------|--------|------------|
| **`B_GET` with `flock`** | Uses host filesystem locks for cache synchronization. In Docker, lock files must be on a mounted volume to work across containers. | Use the shared `$CACHEDIR` volume for lock files |
| **`B_UPDATEPKGBLD()`** | Sources `~/.buildrc` inside the build function. In Docker, this file needs to be mounted. | Mount `~/.buildrc` into the container |
| **Recipe `.files` directories** | Referenced by path (`$RECIPEDIR/$B_NAME.files/B_BUILD`). Must be accessible inside container. | Already handled by mounting `$RECIPEDIR` |
| **`lsb_release`** | Used for distro detection. Must reflect target distro, not host. | Pre-installed in Docker image, or pass as env var |
| **Proxy settings** | `http_proxy`/`https_proxy` set from `$PROXY` config. Must reach inside container. | Pass as `-e` env vars to `docker run`, or configure Docker daemon proxy |
| **Network access in container** | `B_GET` downloads files. Container needs network. | Docker default is network access; use `--network=host` if needed |
| **XDG/yarn cache paths** | Set in `build()` function. Must map to container paths. | Use mounted `$TMPDIR` or container tmpfs |
| **`$HOME` references** | `B_UPDATEPKGBLD` sources `$HOME/.buildrc`. Inside container, `$HOME` differs. | Set `HOME` explicitly in container to match host path, or mount config |
| **User/UID mapping** | Files created inside container owned by root by default | Use `--user` flag or entrypoint script |
| **`B_GET svn` with `--trust-server-cert`** | May need cert configuration inside container | Configure SSL certs in Docker image |

### 6.4 New Capabilities Enabled

| Capability | Description |
|-----------|-------------|
| **Parallel builds** | Multiple containers can build different recipes simultaneously without conflicts |
| **Clean builds guaranteed** | Every build starts from a known-clean state |
| **Multi-distro from one host** | Build for Debian 12, 13, Ubuntu, etc. from a single machine |
| **Reproducibility** | Same base image = same build environment every time |
| **No host pollution** | Build dependencies never touch the host system |
| **ARM builds** | Possible via QEMU (with performance trade-off) |

---

## 7. Implementation Plan

A detailed phased implementation plan is maintained in a separate document:

➡️ **See `docker-implementation-plan.md`**

The plan covers 8 phases (0–7), from bash skill compliance cleanup through Docker infrastructure, RPM support, interactive shell mode, image management, cross-architecture builds, and advanced features. Each phase is independently deployable with specific tasks, code changes, new files, and testing criteria.

---

## 8. Simplified Docker Invocation Sketch

Here's what the core Docker invocation might look like in the build script:

```bash
docker_run_build() {
   local image="$1"
   local build_cmd="$2"

   local docker_args=(
      "--rm"
      "--hostname" "build-${B_NAME}"
   )

   # Keep container on failure for debugging
   test "$DEBUGSHELL" = "1" && docker_args=("${docker_args[@]/--rm/}")

   # Mount volumes (using same paths inside and outside)
   docker_args+=(
      "-v" "${RECIPEDIR}:${RECIPEDIR}"
      "-v" "${CACHEDIR}:${CACHEDIR}"
      "-v" "${DESTDIR}:${DESTDIR}"
      "-v" "${PKGDIR}:${PKGDIR}"
      "-v" "${LOGDIR}:${LOGDIR}"
      "-v" "${HOME}/.buildrc:${HOME}/.buildrc:ro"
   )

   # Pass environment
   docker_args+=(
      "-e" "B_VERSION=${B_VERSION}"
      "-e" "B_INSTALLDIR=${B_INSTALLDIR}"
      "-e" "B_ARCH=${B_ARCH}"
      "-e" "B_NAME=${B_NAME}"
      "-e" "B_BUILDNR=${B_BUILDNR}"
      "-e" "B_CACHEDIR=${CACHEDIR}"
      "-e" "HOME=${HOME}"
   )

   # Proxy settings
   test -n "$PROXY" && docker_args+=("-e" "http_proxy=${PROXY}" "-e" "https_proxy=${PROXY}")

   # Platform for cross-arch
   test -n "$BUILDTARGET" && docker_args+=("--platform" "${BUILDTARGET}")

   docker run "${docker_args[@]}" "$image" bash -c "$build_cmd"
}
```

---

## 9. Answering Your Specific Questions

### Can Docker consolidate multiple Debian versions onto a single machine?

**Yes, absolutely.** This is one of Docker's core strengths. Each build would use the appropriate base image:

- `debian:bookworm` for Debian 12
- `debian:trixie` for Debian 13
- `debian:sid` for Debian unstable
- `ubuntu:noble` for Ubuntu 24.04, etc.

No need for separate VMs or containers running 24/7. The build script pulls the image, runs the build, and cleans up.

### Can you build Raspberry Pi (ARM) packages?

**Yes, but with caveats:**

- **Packages that are arch-independent** (shell scripts, Python pure packages, etc.): Works perfectly, fast.
- **Packages that compile C/C++ code for ARM**: Works via QEMU emulation, but **5–15× slower** than native. Practical for small projects, impractical for large compilations.
- **Alternative:** Use cross-compilation toolchains (`gcc-aarch64-linux-gnu`) on x86 for much better performance, but this requires recipe modifications.

**Recommendation:** Start with same-architecture Docker builds (x86 on x86). Add ARM support later as an opt-in feature, with clear documentation about the performance trade-off. For serious ARM building, consider renting an ARM cloud instance (Oracle Cloud has free ARM VMs) or using cross-compilation.

### Can you still get an interactive shell for recipe development?

**Yes, even better than before.** Currently you need a separate container for each distro running 24/7. With Docker:

- `build --shell bookworm` → instant shell in a Debian 12 environment
- All your recipes, cache, and output directories are mounted
- You can install packages freely (no host pollution)
- When you exit, the container is gone — no cleanup needed

The `-s` (debug shell) flag would also work: on build failure, the container is kept alive and you can `docker exec` into it to investigate.

---

## 10. Risks and Considerations

| Risk | Mitigation |
|------|------------|
| Docker adds complexity | Keep native mode working; Docker is opt-in |
| Volume mount path mismatches | Use same paths inside/outside container |
| File permission issues | Use `--user` flag or entrypoint with UID matching |
| Network issues in container | Use `--network=host` if needed; configure Docker daemon proxy |
| Image pull failures | Pre-pull images; support local image building |
| QEMU performance for ARM | Document clearly; offer cross-compilation alternative |
| `B_GET` cache locking across containers | Use `flock` on mounted volume (already used) |
| Backward compatibility | `BUILDMODE=native` is default; Docker mode requires explicit opt-in |
| Container image staleness | Periodic image rebuilds; version pinning option |

---

## 11. What About `clean` and `debclean`?

These scripts become **unnecessary in Docker mode** — every build starts from a pristine base image. However:

- They remain useful for `BUILDMODE=native`
- They remain useful for general system maintenance outside of build
- **No changes needed** — they just won't be called by the Docker build flow

The `POSTBUILD` config variable (which can be set to `clean -c`) would simply be ignored in Docker mode, or could be repurposed to run a post-build script inside/outside the container.

---

## 12. RPM / Red Hat Package Building

### 12.1 Docker Removes the Infrastructure Barrier

Currently, building RPM packages requires a separate Red Hat / CentOS / Fedora machine. The build script's `MULTI.md` documents this as an open issue with most items still unchecked.

Docker eliminates this requirement: a `centos:9` or `fedora:40` container provides the RPM build environment without needing a dedicated machine.

**However, Docker does NOT write the missing code.** There are two distinct problems:

1. **Infrastructure problem** (need a Red Hat machine) — Docker solves this
2. **Code problem** (the script only knows Debian) — Docker does NOT solve this

### 12.2 Current State of RPM Support in the Code

| Component | Status | Details |
|-----------|--------|----------|
| `require_software()` | Partial | Has a CentOS case for required tools list, nothing else |
| `build_require()` | Debian only | Uses `dpkg-query` + `apt-get` only; no `rpm`/`dnf`/`yum` equivalent |
| `build_require_remove()` | Debian only | Uses `apt-get` only |
| `package()` routing | Partial | Checks `$OS = "CentOS Linux"` before calling `package_rpm()`, but... |
| `package_rpm()` | Stub | Prints "Creating rpm packages is not implemented." and `exit 1` |
| `[RPM]` recipe section | Never read | Defined in test.recipe, but no code parses it |
| `package_torepo()` | Debian only | Only handles `.deb` files |
| `torepo` script | Debian only | Only supports freight-based repos |
| `lsb_release` in `package_deb()` | Debian only | Used for version string; no RPM equivalent |

### 12.3 Code Changes Still Needed for RPM Support

Even with Docker providing the Red Hat environment, the following code must be written:

**`build_require()` — package manager abstraction**

Currently hardcoded to `dpkg-query` and `apt-get`. In Docker mode, the container already IS the right distro, so the simplest approach is to detect the available package manager inside the container:

```bash
build_require() {
   local pkgs="$*"
   if command -v dnf > /dev/null 2>&1; then
      # RPM-based: dnf install
      dnf install -y $pkgs
   elif command -v apt-get > /dev/null 2>&1; then
      # Debian-based: apt-get install
      apt-get update && apt-get install -y $pkgs
   fi
}
```

This is simpler than the current approach because inside a Docker container you're always root, and the container's package manager IS the correct one.

**`package_rpm()` — full implementation needed**

Currently a stub. Must be implemented to:
- Read the `[RPM]` section from the recipe
- Generate a `.spec` file from the recipe section
- Build the RPM using `rpmbuild` or `fakeroot rpm`
- Handle the RPM-specific version string format

**`[RPM]` recipe section parsing**

The test recipe already has an `[RPM]` section, but the code never reads it. Need a function similar to how `[DEB]` sections are parsed and used to generate the `control` file, but generating a `.spec` file instead.

**`package_torepo()` — RPM repo support**

Currently only handles `.deb`. Need to add `.rpm` handling using `createrepo_c` or similar.

**`torepo` script — RPM repo push**

Currently only supports freight. Need an RPM equivalent.

### 12.4 Docker Simplifies the RPM Code Problem

While Docker doesn't write the code, it significantly simplifies the architecture:

- **No dual-OS detection needed in Docker mode** — the container IS the target OS, so the script uses the container's native package manager directly
- **No `sudo` needed** — containers run as root
- **`build_require_remove()` unnecessary** — destroy the container instead
- **OS-specific code paths collapse** — instead of maintaining parallel `apt-get`/`dnf` branches in one script, the container simply has the right tools

### 12.5 What MULTI.md Checklist Items Docker Resolves vs. Doesn't

| MULTI.md Item | Docker Resolves? | Notes |
|--------------|-------------------|-------|
| Separate machine for RPM builds | Yes | Use `centos:9` container |
| Binary storage per distro | Partial | Docker makes it possible, but `dest=dist` config still needs code |
| Per-OS required packages | Partial | Container provides right env, but `[REQUIRED]` section parsing for RPM still needs code |
| Install required software on RPM | Partial | `dnf install` inside container works, but `build_require()` needs `dnf` support |
| RPM package build | No | `package_rpm()` must be implemented from scratch |
| RPM recipe section | No | `[RPM]` section parsing and `.spec` generation must be implemented |
| Push to RPM repo | No | `createrepo` integration must be implemented |
| Update test recipe for RPM | No | Must be done manually |

---

## 13. Summary

| Question | Answer |
|----------|--------|
| Can Docker consolidate Debian 12 + 13 onto one machine? | **Yes** — use different base images per build |
| Can you build ARM/Raspberry Pi packages? | **Yes**, via QEMU emulation (slow for compilation) or cross-compilation (faster, needs recipe changes) |
| Can you still get an interactive shell for development? | **Yes** — even better than current, with `docker exec` or `build --shell` |
| What needs to change? | Add `BUILDMODE=docker` config, Docker image management, modify `build()` and `build_require()` |
| What breaks? | Very little — native mode stays working; Docker is additive |
| Can Docker enable RPM builds? | **Partially** — removes need for Red Hat machine, but RPM packaging code (`package_rpm()`, `.spec` generation, etc.) still needs to be written |
| What's no longer needed? | `clean`/`debclean` in Docker mode; lock file mechanism; `build_require_remove()` |