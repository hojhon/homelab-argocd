#!/bin/bash
set -e

echo "Setting up GitHub Actions runner for ArgoCD..."

# Check if running on the correct host
HOSTNAME=$(hostname)
if [ "$HOSTNAME" != "dev-ops" ]; then
    echo "Error: This script must be run on the dev-ops VM (current host: $HOSTNAME)"
    exit 1
fi

# System update and essential packages
echo "Updating system and installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
    curl \
    git \
    jq \
    wget \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates

# Install kubectl
echo "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Create runner user and directory
sudo useradd -m github-runner -s /bin/bash || true
sudo usermod -aG sudo github-runner
echo "github-runner ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/github-runner

# Create and setup runner directory
sudo mkdir -p /home/github-runner/actions-runner
cd /home/github-runner/actions-runner

# Download and extract the runner
RUNNER_VERSION=2.311.0
sudo curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
sudo tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
sudo rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Set correct ownership
sudo chown -R github-runner:github-runner /home/github-runner/actions-runner

# Install additional dependencies (must not run as root)
sudo -u github-runner ./bin/installdependencies.sh

# Copy K3s config
sudo mkdir -p /home/github-runner/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /home/github-runner/.kube/config
sudo chown -R github-runner:github-runner /home/github-runner/.kube

# Configure the runner
if [ -z "$RUNNER_TOKEN" ]; then
    echo "Please set the RUNNER_TOKEN environment variable"
    echo "You can get this token from GitHub > Repository Settings > Actions > Runners > New self-hosted runner"
    exit 1
fi

# Run config with proper permissions
sudo ./config.sh --unattended \
    --url https://github.com/hojhon/homelab-argocd \
    --token ${RUNNER_TOKEN} \
    --name "dev-ops" \
    --labels "self-hosted,k3s,proxmox" \
    --work _work \
    --runasservice

# Set correct permissions after configuration
sudo chown -R github-runner:github-runner /home/github-runner/actions-runner

# Install and start the service
sudo ./svc.sh install
sudo ./svc.sh start

echo "GitHub Actions runner has been installed and started!"
echo "You can check its status in GitHub > Repository Settings > Actions > Runners"