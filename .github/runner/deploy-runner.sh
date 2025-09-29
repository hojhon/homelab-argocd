#!/bin/bash
set -e

# Check if running on the correct server
HOSTNAME=$(hostname)
if [ "$HOSTNAME" != "dev-ops" ]; then
    echo "This script must be run on the dev-ops server"
    exit 1
fi

# Check for required tools
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed. Installing..."
    curl -fsSL https://get.docker.com | sh
fi

if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Docker Compose is not installed. Installing..."
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p $DOCKER_CONFIG/cli-plugins
    curl -SL https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
fi

# Ensure the runner has access to k3s config
if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
    echo "K3s configuration not found at /etc/rancher/k3s/k3s.yaml"
    exit 1
fi

# Build and start the runner
cd "$(dirname "$0")"
if [ -z "$RUNNER_TOKEN" ]; then
    echo "Please set the RUNNER_TOKEN environment variable"
    echo "You can get this token from GitHub > Repository Settings > Actions > Runners > New self-hosted runner"
    exit 1
fi

docker-compose build
docker-compose up -d

echo "GitHub Actions runner has been deployed!"
echo "You can check its status in GitHub > Repository Settings > Actions > Runners"