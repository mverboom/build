#!/usr/bin/env bash
#
# Fix Docker daemon configuration for the build system.
# This script must be run as root.
#
# Usage: sudo bash fix-docker-proxy.sh

set -e

echo "Fixing Docker daemon configuration..."

# Remove invalid daemon.json (the proxies key is for client config, not daemon)
rm -f /etc/docker/daemon.json

# The systemd drop-in is correct - it sets environment variables
# Verify it exists and is correct
cat /etc/systemd/system/docker.service.d/http-proxy.conf

# Restart Docker daemon
systemctl daemon-reload
systemctl restart docker

echo "Waiting for Docker to start..."
sleep 3

# Check status
systemctl status docker --no-pager || true
docker info > /dev/null 2>&1 && echo "Docker is running!" || echo "Docker failed to start."