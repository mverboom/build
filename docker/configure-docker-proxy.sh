#!/usr/bin/env bash
#
# Configure Docker daemon proxy for the build system.
# This script must be run as root.
#
# Usage: sudo bash configure-docker-proxy.sh

set -e

PROXY="http://wwwproxy.lnw.verboom.net:8080"
NO_PROXY=".lnw.verboom.net,localhost,127.0.0.1"

echo "Configuring Docker daemon proxy: ${PROXY}"

# Create /etc/docker/daemon.json
cat > /etc/docker/daemon.json << EOF
{
  "proxies": {
    "docker-registry": {
      "httpProxy": "${PROXY}",
      "httpsProxy": "${PROXY}",
      "noProxy": "${NO_PROXY}"
    }
  }
}
EOF

# Also create systemd drop-in for Docker daemon
mkdir -p /etc/systemd/system/docker.service.d/
cat > /etc/systemd/system/docker.service.d/http-proxy.conf << EOF
[Service]
Environment="HTTP_PROXY=${PROXY}"
Environment="HTTPS_PROXY=${PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF

# Restart Docker daemon
systemctl daemon-reload
systemctl restart docker

echo "Docker daemon proxy configured and restarted."
echo "Verify with: docker info | grep -i proxy"