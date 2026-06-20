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

# --- Install build dependencies ---

if [[ -n "${BUILD_DEPS:-}" ]]; then
   printf '%s\n' "Installing build dependencies: ${BUILD_DEPS}"
   if command -v apt-get > /dev/null 2>&1; then
      # If apt config is mounted read-only from host, ensure we can still update
      # by using the default container lists directory
      apt-get update > /dev/null 2>&1
      # shellcheck disable=SC2086
      apt-get -y install ${BUILD_DEPS} > /dev/null 2>&1 || {
         printf '%s\n' "Warning: Some build dependencies may not have installed correctly." >&2
      }
   elif command -v dnf > /dev/null 2>&1; then
      # shellcheck disable=SC2086
      dnf install -y ${BUILD_DEPS} > /dev/null 2>&1 || {
         printf '%s\n' "Warning: Some build dependencies may not have installed correctly." >&2
      }
   else
      printf '%s\n' "Error: No supported package manager found." >&2
      exit 1
   fi
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

log_dir="${LOGDIR:-/tmp}"
log_file="${log_dir}/${B_NAME:-build}-${B_ARCH:-all}.log"

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

   if [[ -n "${HOST_UID:-}" ]]; then
      # Run as builduser, capture output to log file and stdout
      su builduser -s /bin/bash /tmp/run-build.sh > "${log_file}" 2>&1
      # Fix ownership of log file (created by root, should be builduser)
      chown builduser:builduser "${log_file}" 2>/dev/null || true
      # Output the log file to stdout so docker logs can capture it
      cat "${log_file}"
   else
      /tmp/run-build.sh 2>&1 | tee "${log_file}"
   fi
elif [[ -f "/tmp/package-cmd.sh" ]]; then
   # Package-only phase (no build command, just package)
   cat > /tmp/run-build.sh <<- 'WRAPPER'
	#!/usr/bin/env bash
	set -e
	source /tmp/build-env.sh
	source /tmp/package-cmd.sh
	WRAPPER
   chmod +x /tmp/run-build.sh

   if [[ -n "${HOST_UID:-}" ]]; then
      su builduser -s /bin/bash /tmp/run-build.sh > "${log_file}" 2>&1
      chown builduser:builduser "${log_file}" 2>/dev/null || true
      cat "${log_file}"
   else
      /tmp/run-build.sh 2>&1 | tee "${log_file}"
   fi
else
   # No build or package command provided, drop to interactive shell
   if [[ -n "${HOST_UID:-}" ]]; then
      # Install sudo for interactive use
      if command -v apt-get > /dev/null 2>&1; then
         apt-get update > /dev/null 2>&1
         apt-get -y install sudo > /dev/null 2>&1 || true
      elif command -v dnf > /dev/null 2>&1; then
         dnf install -y sudo > /dev/null 2>&1 || true
      fi
      # Configure passwordless sudo for builduser
      printf 'builduser ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/builduser
      chmod 440 /etc/sudoers.d/builduser
      exec su builduser -s /bin/bash
   else
      exec /bin/bash
   fi
fi