# Homelab ArgoCD Infrastructure

A complete GitOps-based homelab infrastructure using ArgoCD, Kubernetes (K3s), and Cloudflare tunnels for secure external access.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   GitHub Repo   │    │  GitHub Actions  │    │   K3s Cluster   │
│                 │────│   (CI/CD Runner) │────│                 │
│ • Manifests     │    │                  │    │ • ArgoCD        │
│ • Configs       │    │ • Bootstrap      │    │ • Cloudflared   │
│ • Secrets       │    │ • Deploy         │    │ • Applications  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                                                        │
┌─────────────────┐    ┌──────────────────────┐         │
│  Cloudflare     │    │   External           │         │
│                 │────│     Access           │─────────┘
│ • DNS           │    │                      │
│ • Tunnels       │    │ argocd.com│
│ • SSL/TLS       │    │                      │
└─────────────────┘    └──────────────────────┘
```

## 🚀 Components

### Core Infrastructure
- **Kubernetes Cluster**: K3s single-node cluster
- **GitOps**: ArgoCD for declarative deployments
- **Networking**: Cloudflare tunnels for secure external access
- **CI/CD**: GitHub Actions with self-hosted runner

### Applications
- **ArgoCD**: Web UI at `https://argocd.shinyshiba.com`
- **Cloudflared**: Tunnel service for external connectivity

### Security
- **Secrets Management**: GitHub Secrets + Kubernetes secrets
- **Network Security**: No port forwarding, all traffic through Cloudflare tunnels
- **TLS**: Automatic SSL via Cloudflare

## 📁 Repository Structure

```
homelab-argocd/
├── .github/
│   ├── workflows/
│   │   └── bootstrap-argocd.yaml     # Main deployment workflow
│   └── runner/                       # Self-hosted runner setup
├── apps/
│   ├── argocd/
│   │   └── cloudflared.yaml         # Cloudflare tunnel application for ArgoCD
│   └── hojhon-site/
│       ├── deployment.yaml
│       └── cloudflared.yaml         # Hojhon site workload + tunnel
├── homelab-apps/
│   ├── root-application.yaml        # ArgoCD root app (watches apps/argocd)
# Homelab ArgoCD — concise guide

This repository contains the GitOps configuration used to bootstrap and operate a single-node K3s homelab using ArgoCD and Cloudflare tunnels.

## What this repo does (short)
- Bootstraps ArgoCD control plane and necessary namespaces.
- Creates Kubernetes secrets from GitHub Actions (tokens are provided via GitHub Secrets).
- Deploys a root ArgoCD `Application` which watches runtime manifests under `apps/argocd/`.
- Provides a small `deploy-app` workflow for applying new ArgoCD `Application` manifests from `homelab-apps/`.

## Current structure
```
homelab-argocd/
├── .github/
│   └── workflows/
│       ├── bootstrap-argocd.yaml   # bootstraps ArgoCD and creates initial apps/secrets
│       └── deploy-app.yaml         # apply App manifests from homelab-apps/
├── apps/
│   ├── argocd/                     # manifests ArgoCD watches (root app -> recurse: true)
│   │   └── cloudflared.yaml        # cloudflared tunnel for ArgoCD
│   └── hojhon-site/                # example workload + tunnel for user site
│       ├── deployment.yaml
│       └── cloudflared.yaml
├── homelab-apps/                   # ArgoCD Application manifests (app-of-apps)
│   ├── root-application.yaml       # root Application that points to apps/argocd
│   └── hojhon-site-app.yaml        # application manifest to register hojhon-site
└── README.md
```

## How it works (concise)
- App-of-apps: `homelab-apps/root-application.yaml` is applied into the `argocd` namespace. It points to `apps/argocd/` and uses `directory.recurse: true`. Anything placed under `apps/argocd/` is then automatically managed by ArgoCD.
- Application manifests (the `homelab-apps/` files) are ArgoCD `Application` resources. These must be applied to the cluster (into namespace `argocd`) to register child applications with ArgoCD. Use `deploy-app` workflow to add them without re-running the full bootstrap.

## Adding a new app (recommended layout)
- For a new workload that ArgoCD should manage directly:
  1. Create `apps/argocd/<my-app>/` and put Kubernetes manifests or a Helm chart there.
  2. Commit & push — the root Application will detect and sync the changes.

- To add a new ArgoCD Application (so it appears in the ArgoCD UI as an Application):
  1. Create `homelab-apps/<my-app>-app.yaml` containing an `Application` CR that points to `apps/argocd/<my-app>`.
  2. Run the `Deploy App (GitOps deployer)` workflow and pass the filename (or push and let CI detect it if configured).

## Bootstrap vs routine deploy
- bootstrap-argocd.yaml (one-time): installs ArgoCD, creates namespaces, and seeds initial secrets and root Application.
- deploy-app.yaml (routine): applies a single `Application` manifest into `argocd/` so ArgoCD starts managing that app.

## Secrets and persistence
- Tokens and secrets should be stored in GitHub Actions secrets. The bootstrap workflow creates Kubernetes secrets in the correct namespace and sets policies so Helm doesn't overwrite them.
- Do not commit secret values to the repo.

## Quick commands
- Show ArgoCD applications:

```bash
kubectl get applications -n argocd
```

- Apply a new ArgoCD Application manually (alternative to the workflow):

```bash
kubectl apply -f homelab-apps/my-app-app.yaml
```

- Sync an application using ArgoCD CLI:

```bash
argocd app sync <app-name>
```

## Notes
- The repo supports adding more apps. Follow the app-of-apps pattern: runtime manifests in `apps/argocd/`; ArgoCD Application CRs in `homelab-apps/`.
- `deploy-app` is the safe path to register new Applications without re-running bootstrap.

---

If you want, I can also add a short example `vault` app and a `homelab-apps/vault-app.yaml` to show the exact layout. Tell me to proceed and I'll add it.
## 🔐 Security Considerations


