# Homelab ArgoCD Infrastructure

A complete GitOps-based homelab infrastructure using ArgoCD, Kubernetes (K3s), and Cloudflare tunnels for secure external access.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   GitHub Repo   │    │  GitHub Actions  │    │   K3s Cluster   │
│                 │────│   (CI/CD Runner) │────│                 │
│ • Manifests     │    │                  │    │ • ArgoCD        │
│ • Templates     │    │ • Bootstrap      │    │ • Applications  │
│ • Configs       │    │ • Deploy/Delete  │    │ • Cloudflared   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                                                        │
┌─────────────────┐    ┌──────────────────────┐         │
│  Cloudflare     │    │   External Access    │         │
│                 │────│                      │─────────┘
│ • DNS           │    │                      │
│ • Tunnels       │    │ • jhonherrera.site   │
│ • SSL/TLS       │    │                      │
└─────────────────┘    └──────────────────────┘
```

## 🚀 Components

### Core Infrastructure
- **Kubernetes Cluster**: K3s single-node cluster
- **GitOps**: ArgoCD for declarative deployments  
- **Networking**: Traefik ingress + Cloudflare tunnels for external apps
- **CI/CD**: GitHub Actions with self-hosted runner

### Applications
- **ArgoCD**: Web UI at `http://argo.shinyshiba.com` (local DNS) 
- **Hojhon-Site**: Personal website at `https://jhonherrera.site`
- **Vault**: Internal secrets management (cluster-internal only)

### Security
- **Secrets Management**: GitHub Secrets + ArgoCD ignoreDifferences pattern
- **Network Security**: ArgoCD uses local DNS, apps use Cloudflare tunnels
- **TLS**: Automatic SSL via Cloudflare for external services

## 📁 Repository Structure

```
homelab-argocd/
├── .github/
│   ├── workflows/
│   │   ├── bootstrap-argocd.yaml     # Initial cluster setup
│   │   ├── deploy-app.yaml          # App deployment  
│   │   ├── delete-app.yaml          # App removal
│   │   └── refresh-argocd-apps.yaml # Force sync
├── templates/                       # GitOps templates
│   ├── ONBOARDING.md               # App onboarding guide
│   ├── argocd-app.yaml            # ArgoCD app template
│   └── web-app/                   # Web app templates
│       ├── deployment.yaml
│       └── cloudflared.yaml
├── apps/
│   ├── argocd/                      # ArgoCD configuration
│   │   ├── ingress.yaml            # Local Traefik ingress  
│   │   └── argocd-config.yaml      # ArgoCD server config
│   ├── hojhon-site/                # Personal website
│   │   ├── deployment.yaml         # App deployment + service
│   │   └── cloudflared.yaml        # Cloudflare tunnel config
│   └── vault/                      # HashiCorp Vault
│       ├── application.yaml        # Vault ArgoCD app
│       └── values-helm.yaml        # Helm values
├── homelab-apps/                   # ArgoCD Application definitions
│   ├── root-application.yaml      # Root app (watches apps/argocd)
│   ├── hojhon-site-app.yaml       # Hojhon site application
│   └── vault-app.yaml             # Vault application
├── scripts/
│   └── manage-cloudflared-secrets.sh # Tunnel secret management
└── README.md

## 🎯 Quick Start

### Prerequisites
- K3s cluster running
- GitHub self-hosted runner on cluster node
- Cloudflare tunnel tokens in GitHub Secrets

### 1. Bootstrap ArgoCD
```bash
# Run via GitHub Actions
gh workflow run "1 - Bootstrap ArgoCD"
```

### 2. Access ArgoCD UI
Add to `/etc/hosts`:
```
192.168.1.164 argo.shinyshiba.com
```
Then access: `http://argo.shinyshiba.com`

### 3. Add New Applications
```bash
# Copy template
cp -r templates/web-app apps/my-new-app

# Edit files (change CHANGE_ME_* placeholders)
# - apps/my-new-app/deployment.yaml
# - apps/my-new-app/cloudflared.yaml

# Create ArgoCD app
cp templates/argocd-app.yaml homelab-apps/my-new-app-app.yaml
# Edit placeholders

# Commit and push
git add apps/my-new-app homelab-apps/my-new-app-app.yaml
git commit -m "Add my-new-app"
git push
```

### 4. Delete Applications
```bash
# Use GitHub Actions workflow
gh workflow run "Delete Application from ArgoCD" \
  -f app_name=my-app \
  -f namespace=my-app \
  -f delete_tunnel=true \
  -f confirm_deletion=DELETE
```

## 🔧 Management

### Secret Management
Cloudflare tunnel tokens are managed via:
```bash
./scripts/manage-cloudflared-secrets.sh
```

### Force Sync Applications
```bash
gh workflow run "Refresh ArgoCD Applications"
```

## 📚 Documentation

- **[Application Onboarding Guide](templates/ONBOARDING.md)** - How to add new apps
- **[Templates](templates/)** - GitOps templates for new applications

## 🔒 Security Model

### ArgoCD Access
- **Local DNS**: `argo.shinyshiba.com` resolves to cluster IP
- **No external exposure**: ArgoCD not accessible from internet  
- **Ingress**: Traefik handles local routing

### Application Secrets
- **ignoreDifferences**: ArgoCD ignores tunnel token changes
- **Persistent secrets**: Tokens don't get overwritten by GitOps
- **GitHub Secrets**: Sensitive values stored in repository secrets

### Network Security
- **Cloudflare tunnels**: External apps use encrypted tunnels
- **No port forwarding**: All external access through Cloudflare
- **TLS termination**: Cloudflare handles SSL certificates

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


