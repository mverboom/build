#!/usr/bin/env bash
#
# Docker container entrypoint for Build system
#
# Runs as root to install dependencies, then switches to builduser
# (with the same UID/GID as the host user) to execute build commands.
#
# Environment variables:
#   BUILD_DEPS  - Space-separated list of packages to install
#   HOST_UID    - UID of the host user (used to create builduser)
#   HOST_GID    - GID of the host user (used to create builduser)
#   BUILDMODE   - Set to "docker" inside container
#   HOME        - Home directory path (matching host)
#
# Mounted files:
#   /opt/build/build-env.sh   - Build environment (variables + functions)
#   /opt/build/build-cmd.sh   - Build command script (recipe BUILD section)
#   /opt/build/package-cmd.sh - Package command script (optional, for Phase 2)

set -u

# Non-interactive container: silence debconf warnings such as
# "unable to initialize frontend: Dialog" during package installs.
export DEBIAN_FRONTEND=noninteractive

# Run a package-manager (or other setup) command, capturing its output.
# Errors are ALWAYS surfaced (printed to stderr and appended to the build log);
# the full successful output is shown only when B_VERBOSE=1.
# Parameters: log_file  command [args...]
# Returns the command's exit status.
run_pkg() {
   local logf="$1"; shift
   local rc
   if [[ "${B_VERBOSE:-0}" == "1" ]]; then
      printf '## %s\n' "$*"
      "$@" 2>&1 | tee -a "$logf"
      rc=${PIPESTATUS[0]}
   else
      "$@" > "$logf" 2>&1
      rc=$?
      if (( rc != 0 )); then
         printf '## Command failed (exit %s): %s\n' "$rc" "$*" >&2
         cat "$logf" >&2
      fi
   fi
   return "$rc"
}

# Run a script in the build environment, as builduser when one is created
# (HOST_UID set), appending output to the build log. In verbose mode stream
# output live to stdout (picked up by `docker logs -f` on the host) via tee,
# so progress is visible while the build runs; on failure in non-verbose
# mode, surface the captured log so errors are visible (matching run_pkg
# behaviour for dependency installs). Fixes the log file ownership when run
# as builduser (the log is created/extended by root, should be builduser).
# Parameters: script_path
# Returns the script's exit status.
run_builduser() {
   local script="$1"
   local rc
   if [[ -n "${HOST_UID:-}" ]]; then
      if [[ "${B_VERBOSE:-0}" == "1" ]]; then
         su builduser -s /bin/bash "$script" 2>&1 | tee -a "${log_file}"
         rc=${PIPESTATUS[0]}
      else
         su builduser -s /bin/bash "$script" >> "${log_file}" 2>&1
         rc=$?
         (( rc != 0 )) && cat "${log_file}"
      fi
      chown builduser:builduser "${log_file}" 2>/dev/null || true
   else
      if [[ "${B_VERBOSE:-0}" == "1" ]]; then
         "$script" 2>&1 | tee -a "${log_file}"
         rc=${PIPESTATUS[0]}
      else
         "$script" >> "${log_file}" 2>&1
         rc=$?
         (( rc != 0 )) && cat "${log_file}"
      fi
   fi
   return "$rc"
}

# When /tmp is a bind mount of a host BUILDDOCKERTMP subdirectory, clean it on
# exit so root-owned build artifacts (created by apt/dpkg/etc. during the
# build) are removed by root -- the host builduser cannot delete them. Each
# build gets its own fresh subdirectory (created by the host script), so there
# are no leftovers from previous runs to clean at start; this runs at exit
# instead. The read-only build scripts live under /opt/build (outside the /tmp
# bind mount), so /tmp holds only generated build artifacts and can be wiped
# without excluding any mount points. On the default ephemeral /tmp
# (B_DOCKERTMP=0) this is a no-op. Runs as root (the entrypoint process), so
# it can remove files owned by both root and builduser.
# Installed before the dependency-setup section: that path exits early on
# failure, and a skipped cleanup leaves a root-owned /tmp/build-deps.log in
# the bind-mounted buildtmp subdir that the host builduser can never delete.
bdt_cleanup() {
   [[ "${B_DOCKERTMP:-0}" == "1" ]] || return 0
   find /tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
}
trap bdt_cleanup EXIT

# Build log file (defined early so dependency output can be appended to it).
log_dir="${LOGDIR:-/tmp}"
log_file="${log_dir}/${B_DISTRO:-unknown}/${B_NAME:-build}-${B_ARCH:-all}.log"
deps_log="/tmp/build-deps.log"
: > "$deps_log"
dep_failed=0

# --- Install build dependencies ---

if [[ -n "${BUILD_DEPS:-}" ]]; then
   printf '%s\n' "Installing build dependencies: ${BUILD_DEPS}"
   if command -v apt-get > /dev/null 2>&1; then
      # apt-get update must succeed before we attempt the install. If either
      # fails the build is aborted below -- a build must never run with missing
      # build dependencies (it would otherwise produce a bogus package).
      if run_pkg "$deps_log" apt-get update; then
         # shellcheck disable=SC2086
         run_pkg "$deps_log" apt-get -y install ${BUILD_DEPS} || dep_failed=1
      else
         dep_failed=1
      fi
   else
      printf '%s\n' "Error: apt-get not found (build images are Debian-based)." >&2
      exit 1
   fi
fi

# Persist dependency setup output into the build log when verbose or on failure,
# so errors are recoverable from the log file (not only from docker logs).
if [[ "${B_VERBOSE:-0}" == "1" ]] || (( dep_failed != 0 )); then
   printf '### Dependency setup output\n' >> "$log_file"
   cat "$deps_log" >> "$log_file"
fi

# Abort if dependency setup failed: do NOT proceed to the build, so a failed
# dependency install can never lead to a "succeeded" build, an empty package,
# or a push to the repository.
if (( dep_failed != 0 )); then
   printf '%s\n' "## Aborting: build dependency setup failed (see output above)." >&2
   exit 1
fi

# --- Create build user matching host UID/GID ---

if [[ -n "${HOST_UID:-}" ]]; then
   # Create group if it doesn't exist
   if ! getent group builduser > /dev/null 2>&1; then
      groupadd -g "${HOST_GID:-${HOST_UID}}" builduser
   fi

   # Create user if it doesn't exist
   # Use -M to skip home dir creation; $HOME is created below in the
   # container's writable layer (only specific sub-trees are bind-mounted).
   if ! id -u builduser > /dev/null 2>&1; then
      useradd -u "${HOST_UID}" -g "${HOST_GID:-${HOST_UID}}" -M builduser
   fi

   # Ensure mount directories are writable by builduser
   #
   # $HOME itself is NOT bind-mounted as a whole (only specific sub-trees are
   # mounted: recipes, cache, build, log, packages, etc, .buildrc, .ssh,
   # .gnupg, .gitconfig). The unmounted $HOME path exists only in the
   # container's writable layer, so it must be created and owned by builduser
   # for tools that write caches into $HOME/.<tool> (cargo, gradle, ...) --
   # those writes are deliberately ephemeral and discarded with the container.
   mkdir -p "$HOME" 2>/dev/null || true
   chown builduser:builduser "$HOME" 2>/dev/null || true

   # Configure passwordless sudo for builduser in ALL modes, not just the
   # interactive dev shell: a meta recipe's BUILD section calls `build` again
   # for each component, and those nested builds run natively in this
   # container, where build_require() installs dependencies via sudo.
   # (The build images ship sudo; the interactive branch below also installs
   # it for pulled images.)
   printf 'builduser ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/builduser
   chmod 440 /etc/sudoers.d/builduser
fi

# --- Execute build and/or package commands ---

if [[ -f "/opt/build/build-cmd.sh" ]]; then
   # Build phase: run build command, optionally followed by package command
   # Write a wrapper script that sources the env and runs the commands.
   cat > /tmp/run-build.sh <<- 'WRAPPER'
	#!/usr/bin/env bash
	set -e
	source /opt/build/build-env.sh
	cd /tmp || exit 1
	source /opt/build/build-cmd.sh
	WRAPPER

   # If package command exists, append it to the wrapper
   if [[ -f "/opt/build/package-cmd.sh" ]]; then
      printf '\nsource /opt/build/package-cmd.sh\n' >> /tmp/run-build.sh
   fi

   chmod +x /tmp/run-build.sh

   # Run the wrapper and capture its real exit code (previously the exit code
   # of `cat`/`tee` was used, masking build failures).
   run_builduser /tmp/run-build.sh
   build_rc=$?

   # On failure with DEBUGSHELL enabled, keep the container alive so the user
   # can attach (docker exec -it) to inspect the build environment. A sentinel
   # file written to LOGDIR lets the host detect this state and drive the
   # interactive debug session. Otherwise exit with the build's exit code.
   if (( build_rc != 0 )) && [[ "${DEBUGSHELL:-}" == "1" ]]; then
      printf '%s\n' "## Build failed (exit ${build_rc}). DEBUGSHELL: keeping container alive for inspection."
      : > "${log_dir}/.build-debug-${_BUILD_DEBUG_TOKEN:-nodebug}" 2>/dev/null || true
      # Stay alive until the host removes the sentinel (debug session finished)
      # or a safety timeout expires, so an interrupted host run cannot leak the
      # container forever.
      waited=0
      while [[ -f "${log_dir}/.build-debug-${_BUILD_DEBUG_TOKEN:-nodebug}" ]] && (( waited < 3600 )); do
         sleep 10
         waited=$((waited + 10))
      done
   fi
   exit "${build_rc}"
elif [[ -f "/opt/build/package-cmd.sh" ]]; then
   # Package-only phase (no build command, just package)
   cat > /tmp/run-build.sh <<- 'WRAPPER'
	#!/usr/bin/env bash
	set -e
	source /opt/build/build-env.sh
	source /opt/build/package-cmd.sh
	WRAPPER
   chmod +x /tmp/run-build.sh

   run_builduser /tmp/run-build.sh
   pkg_rc=$?
   exit "${pkg_rc}"
else
   # No build or package command provided, drop to interactive shell
   if [[ -n "${HOST_UID:-}" ]]; then
      # Install sudo for interactive use
      if command -v apt-get > /dev/null 2>&1; then
         run_pkg "$deps_log" apt-get update || true
         run_pkg "$deps_log" apt-get -y install sudo || true
      fi
      # Passwordless sudo for builduser is configured above for all modes.
      exec su - builduser -s /bin/bash
   else
      exec /bin/bash
   fi
fi
