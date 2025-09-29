#!/bin/bash
set -e

# Function for logging
log() {
    echo "➜ $1"
}

error() {
    echo "❌ $1"
    exit 1
}

# Check if script is run with sudo
if [ "$EUID" -ne 0 ]; then 
    error "Please run with sudo"
fi

log "Setting up GitHub Actions runner for ArgoCD..."

# Check if running on the correct host
HOSTNAME=$(hostname)
if [ "$HOSTNAME" != "dev-ops" ]; then
    error "This script must be run on the dev-ops VM (current host: $HOSTNAME)"
fi

# System update and essential packages
log "Updating system and installing dependencies..."
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
log "Creating runner directory..."
mkdir -p /home/github-runner/actions-runner
cd /home/github-runner/actions-runner

# Download and extract the runner
log "Downloading GitHub Actions runner..."
RUNNER_VERSION=2.311.0
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Set correct ownership
log "Setting correct permissions..."
chown -R github-runner:github-runner /home/github-runner/actions-runner

# Install additional dependencies (must not run as root)
log "Installing runner dependencies (as github-runner user)..."

# Ensure proper permissions and run dependencies installation
cd /home/github-runner/actions-runner
chown -R github-runner:github-runner .
chmod +x ./bin/installdependencies.sh

if ! sudo -H -u github-runner bash -c 'cd /home/github-runner/actions-runner && sudo ./bin/installdependencies.sh'; then
    error "Failed to install runner dependencies"
fi

# Setup Kubernetes access
log "Setting up Kubernetes configuration..."
if [ ! -f "/etc/rancher/k3s/k3s.yaml" ]; then
    error "K3s config not found at /etc/rancher/k3s/k3s.yaml"
fi

mkdir -p /home/github-runner/.kube
cp /etc/rancher/k3s/k3s.yaml /home/github-runner/.kube/config
sudo chown -R github-runner:github-runner /home/github-runner/.kube
sudo chmod 600 /home/github-runner/.kube/config

# Verify runner token
if [ -z "$RUNNER_TOKEN" ]; then
    error "Please set the RUNNER_TOKEN environment variable"
fi

log "Configuring GitHub Actions runner..."
# Configure runner as github-runner user
sudo -u github-runner bash -c 'cd /home/github-runner/actions-runner && ./config.sh --unattended \
    --url https://github.com/hojhon/homelab-argocd \
    --token "'${RUNNER_TOKEN}'" \
    --name "dev-ops" \
    --labels "self-hosted,k3s,proxmox" \
    --work _work \
    --runasservice'

log "Installing runner service..."
cd /home/github-runner/actions-runner
./svc.sh install root

log "Starting runner service..."
./svc.sh start

log "✅ GitHub Actions runner installation complete!"
log "Check runner status at: https://github.com/hojhon/homelab-argocd/settings/actions/runners"

echo "GitHub Actions runner has been installed and started!"
echo "You can check its status in GitHub > Repository Settings > Actions > Runners"