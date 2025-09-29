# Homelab ArgoCD Configuration

This repository contains the GitOps configuration for a homelab Kubernetes cluster using ArgoCD.

## Components

- **ArgoCD**: Manages all deployments in the cluster
- **Cloudflared**: Provides secure access through Cloudflare Tunnels

## Structure

```
.
├── apps/
│   ├── base/             # Base configurations
│   │   ├── argocd/      # ArgoCD installation
│   │   └── cloudflared/ # Cloudflare tunnel
│   └── overlays/        # Environment-specific configs
│       └── prod/        # Production environment
└── .github/
    └── workflows/       # GitHub Actions workflows
```

## Setup

1. Fork this repository
2. Configure GitHub Secrets:
   - `KUBE_CONFIG`: Kubernetes configuration file
   - `ARGOCD_ADMIN_PASSWORD`: Desired ArgoCD admin password
   - `CLOUDFLARE_TUNNEL_TOKEN`: Cloudflare tunnel token

3. Apply the root application:
   ```bash
   kubectl apply -f apps/overlays/prod/root-application.yaml
   ```

## Access

- ArgoCD UI: https://argocd.shinyshiba.com
- Authentication: Managed through GitHub Actions

## Security
- Cloudflare Tunnel provides secure access without port forwarding
- No sensitive data stored in the repository