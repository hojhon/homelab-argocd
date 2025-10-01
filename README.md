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
│ • Tunnels       │    │ argocd.shinyshiba.com│
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
│   └── cloudflared.yaml             # Cloudflare tunnel application
├── homelab-apps/
│   └── root-application.yaml        # ArgoCD root app (if using app-of-apps)
├── cloudflared-secret.yaml          # ⚠️  LEAKED - MOVE TO .gitignore
├── k3s-config.yaml                  # ⚠️  LEAKED - MOVE TO .gitignore  
└── README.md
```

## 🔧 Deployment Process

### Prerequisites
1. **K3s Cluster**: Single-node Kubernetes cluster
2. **GitHub Secrets**: Required environment variables
3. **Cloudflare Account**: With tunnel configured
4. **Self-hosted Runner**: GitHub Actions runner on cluster

### GitHub Secrets Required
```bash
ARGOCD_ADMIN_PASSWORD    # ArgoCD admin password
CLOUDFLARE_TUNNEL_TOKEN  # Cloudflare tunnel token
ARGO_PAT                # GitHub Personal Access Token
```

### Bootstrap Deployment
1. **Trigger Workflow**: Manual trigger of `bootstrap-argocd` workflow
2. **Create Namespaces**: `argocd` and `cloudflare`
3. **Install ArgoCD**: Official upstream manifests
4. **Configure Secrets**: Admin password and tunnel token
5. **Add Repository**: GitHub repo with PAT authentication
6. **Deploy Applications**: Root application manages child apps

### Manual Bootstrap (Alternative)
```bash
# 1. Create namespaces
kubectl create namespace argocd
kubectl create namespace cloudflare

# 2. Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Create secrets
kubectl -n argocd create secret generic argocd-secret \
  --from-literal=admin.password="YOUR_PASSWORD" \
  --from-literal=admin.passwordMtime="$(date +%FT%T%Z)" \
  --from-literal=server.secretkey="$(openssl rand -base64 32)"

kubectl -n cloudflare create secret generic cloudflared-cloudflare-tunnel-remote \
  --from-literal=tunnelToken="YOUR_TUNNEL_TOKEN"

# 4. Deploy root application
kubectl apply -f homelab-apps/root-application.yaml
```

## 🔐 Security Considerations

### Access Control
- **ArgoCD**: Admin access via dynamically generated password
- **External Access**: Only through Cloudflare tunnels
- **Repository**: Private repo with PAT authentication

### Network Security
- **No Port Forwarding**: All external access via Cloudflare
- **TLS Termination**: At Cloudflare edge
- **Internal Traffic**: Service mesh within cluster

### Secrets Management
- **GitHub Secrets**: Sensitive data stored in GitHub
- **Kubernetes Secrets**: Created dynamically by workflows
- **Rotation**: Manual rotation of PATs and tunnel tokens

## 🛠️ Operations

### Accessing ArgoCD
```bash
# Option 1: External URL (recommended)
https://argocd.shinyshiba.com

# Option 2: Port forward (debugging)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Then: https://localhost:8080

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode
```

### Managing Applications
```bash
# List applications
kubectl get applications -n argocd

# Sync application
argocd app sync <app-name>

# Get application status
argocd app get <app-name>
```

### Monitoring
```bash
# Check ArgoCD status
kubectl get pods -n argocd

# Check Cloudflared status  
kubectl get pods -n cloudflare

# View logs
kubectl logs -n cloudflare -l app=cloudflared
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

## 🔄 Maintenance

### Updating ArgoCD
1. Update workflow to new ArgoCD version
2. Run bootstrap workflow
3. Verify all applications sync

### Rotating Secrets
1. Update GitHub Secrets
2. Re-run bootstrap workflow
3. Restart affected pods

### Backup & Recovery
```bash
# Backup ArgoCD configuration
kubectl get applications -n argocd -o yaml > argocd-backup.yaml

# Restore (after cluster rebuild)
kubectl apply -f argocd-backup.yaml
```

## 🚨 Troubleshooting

### Common Issues

#### ArgoCD Login Failed
```bash
# Check admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode

# Reset password
kubectl -n argocd delete secret argocd-initial-admin-secret
kubectl -n argocd rollout restart deployment argocd-server
```

#### Applications OutOfSync
```bash
# Force sync
argocd app sync <app-name> --force

# Check repository connection
argocd repo list
```

#### Cloudflare Tunnel Issues
```bash
# Check tunnel status
kubectl logs -n cloudflare -l app=cloudflared

# Verify secret
kubectl -n cloudflare get secret cloudflared-cloudflare-tunnel-remote -o yaml
```

## 📈 Future Enhancements

- [ ] **Monitoring**: Prometheus + Grafana stack
- [ ] **Logging**: ELK/Loki stack for centralized logging  
- [ ] **Backup**: Automated backup solution (Velero)
- [ ] **Security**: Policy engine (OPA Gatekeeper)
- [ ] **Multi-cluster**: Expand to multiple K3s nodes
- [ ] **Service Mesh**: Istio for advanced networking
- [ ] **GitOps**: Flux as alternative to ArgoCD

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Test changes in dev environment
4. Submit pull request

## 📄 License

MIT License - see LICENSE file for details.

---

**⚠️ Important**: This repository contains infrastructure code. Always review changes carefully before deployment.

- **ArgoCD**: Manages all deployments in the cluster
- **Cloudflared**: Provides secure access through Cloudflare Tunnels

## Structure

