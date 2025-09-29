#!/bin/bash

RUNNER_VERSION=2.311.0

# Download and extract the runner
cd /home/runner
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Configure the runner
./config.sh --unattended --url https://github.com/hojhon/homelab-argocd --token ${RUNNER_TOKEN}

# Start the runner
./run.sh