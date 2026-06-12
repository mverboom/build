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
#   /tmp/build-env.sh - Build environment (variables + functions)
#   /tmp/build-cmd.sh - Build command script (recipe BUILD section)

set -u

# --- Install build dependencies ---

if [[ -n "${BUILD_DEPS:-}" ]]; then
   printf '%s\n' "Installing build dependencies: ${BUILD_DEPS}"
   if command -v apt-get > /dev/null 2>&1; then
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
   if ! id -u builduser > /dev/null 2>&1; then
      useradd -u "${HOST_UID}" -g "${HOST_GID:-${HOST_UID}}" -m builduser
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

# --- Execute build command ---

if [[ -f "/tmp/build-cmd.sh" ]]; then
   # Write a wrapper script that sources the env and runs the build
   cat > /tmp/run-build.sh << 'WRAPPER'
#!/usr/bin/env bash
set -e
source /tmp/build-env.sh
cd /tmp || exit 1
source /tmp/build-cmd.sh
WRAPPER
   chmod +x /tmp/run-build.sh

   if [[ -n "${HOST_UID:-}" ]]; then
      exec su builduser -s /bin/bash -c /tmp/run-build.sh
   else
      exec /tmp/run-build.sh
   fi
else
   # No build command provided, drop to interactive shell
   if [[ -n "${HOST_UID:-}" ]]; then
      exec su builduser -s /bin/bash
   else
      exec /bin/bash
   fi
fi