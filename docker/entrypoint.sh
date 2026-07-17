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
#   /tmp/build-env.sh   - Build environment (variables + functions)
#   /tmp/build-cmd.sh   - Build command script (recipe BUILD section)
#   /tmp/package-cmd.sh - Package command script (optional, for Phase 2)

set -u

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

# Build log file (defined early so dependency output can be appended to it).
log_dir="${LOGDIR:-/tmp}"
log_file="${log_dir}/${B_NAME:-build}-${B_ARCH:-all}.log"
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
   elif command -v dnf > /dev/null 2>&1; then
      # shellcheck disable=SC2086
      run_pkg "$deps_log" dnf install -y ${BUILD_DEPS} || dep_failed=1
   else
      printf '%s\n' "Error: No supported package manager found." >&2
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
   # Use -M to skip home dir creation (it's mounted from the host)
   if ! id -u builduser > /dev/null 2>&1; then
      useradd -u "${HOST_UID}" -g "${HOST_GID:-${HOST_UID}}" -M builduser
   fi

   # Ensure mount directories are writable by builduser
   for dir in "${B_INSTALLDIR:-}" "${B_CACHEDIR:-}" "${DESTDIR:-}" "${LOGDIR:-}" "${PKGDIR:-}"; do
      if [[ -n "${dir:-}" ]] && [[ -d "${dir}" ]]; then
         chown -R builduser:builduser "${dir}" 2>/dev/null || true
      fi
   done
else
   # No UID provided, run as root
   :
fi

# --- Execute build and/or package commands ---

if [[ -f "/tmp/build-cmd.sh" ]]; then
   # Build phase: run build command, optionally followed by package command
   # Write a wrapper script that sources the env and runs the commands.
   cat > /tmp/run-build.sh <<- 'WRAPPER'
	#!/usr/bin/env bash
	set -e
	source /tmp/build-env.sh
	cd /tmp || exit 1
	source /tmp/build-cmd.sh
	WRAPPER

   # If package command exists, append it to the wrapper
   if [[ -f "/tmp/package-cmd.sh" ]]; then
      printf '\nsource /tmp/package-cmd.sh\n' >> /tmp/run-build.sh
   fi

   chmod +x /tmp/run-build.sh

   # Run the wrapper and capture its real exit code (previously the exit code
   # of `cat`/`tee` was used, masking build failures).
   build_rc=0
   if [[ -n "${HOST_UID:-}" ]]; then
      # Run as builduser, capturing all output to the log file (append, so
      # any dependency-setup output already written to the log is preserved).
      # The log is echoed to stdout only in verbose mode, or on failure so
      # errors are visible (matching run_pkg behaviour for dependency installs).
      su builduser -s /bin/bash /tmp/run-build.sh >> "${log_file}" 2>&1
      build_rc=$?
      # Fix ownership of log file (created by root, should be builduser)
      chown builduser:builduser "${log_file}" 2>/dev/null || true
      if [[ "${B_VERBOSE:-0}" == "1" ]] || (( build_rc != 0 )); then
         cat "${log_file}"
      fi
   else
      /tmp/run-build.sh >> "${log_file}" 2>&1
      build_rc=$?
      if [[ "${B_VERBOSE:-0}" == "1" ]] || (( build_rc != 0 )); then
         cat "${log_file}"
      fi
   fi

   # On failure with DEBUGSHELL enabled, keep the container alive so the user
   # can attach (docker exec -it) to inspect the build environment. A sentinel
   # file written to LOGDIR lets the host detect this state and drive the
   # interactive debug session. Otherwise exit with the build's exit code.
   if (( build_rc != 0 )) && [[ "${DEBUGSHELL:-}" == "1" ]]; then
      printf '%s\n' "## Build failed (exit ${build_rc}). DEBUGSHELL: keeping container alive for inspection."
      : > "${log_dir}/.build-debug-${_BUILD_DEBUG_TOKEN:-nodebug}" 2>/dev/null || true
      # Block PID 1 so the container stays running until the host removes it.
      tail -f /dev/null
   fi
   exit "${build_rc}"
elif [[ -f "/tmp/package-cmd.sh" ]]; then
   # Package-only phase (no build command, just package)
   cat > /tmp/run-build.sh <<- 'WRAPPER'
	#!/usr/bin/env bash
	set -e
	source /tmp/build-env.sh
	source /tmp/package-cmd.sh
	WRAPPER
   chmod +x /tmp/run-build.sh

   pkg_rc=0
   if [[ -n "${HOST_UID:-}" ]]; then
      su builduser -s /bin/bash /tmp/run-build.sh >> "${log_file}" 2>&1
      pkg_rc=$?
      chown builduser:builduser "${log_file}" 2>/dev/null || true
      if [[ "${B_VERBOSE:-0}" == "1" ]] || (( pkg_rc != 0 )); then
         cat "${log_file}"
      fi
   else
      /tmp/run-build.sh >> "${log_file}" 2>&1
      pkg_rc=$?
      if [[ "${B_VERBOSE:-0}" == "1" ]] || (( pkg_rc != 0 )); then
         cat "${log_file}"
      fi
   fi
   exit "${pkg_rc}"
else
   # No build or package command provided, drop to interactive shell
   if [[ -n "${HOST_UID:-}" ]]; then
      # Install sudo for interactive use
      if command -v apt-get > /dev/null 2>&1; then
         run_pkg "$deps_log" apt-get update || true
         run_pkg "$deps_log" apt-get -y install sudo || true
      elif command -v dnf > /dev/null 2>&1; then
         run_pkg "$deps_log" dnf install -y sudo || true
      fi
      # Configure passwordless sudo for builduser
      printf 'builduser ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/builduser
      chmod 440 /etc/sudoers.d/builduser
      exec su builduser -s /bin/bash
   else
      exec /bin/bash
   fi
fi