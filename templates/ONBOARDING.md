# GitOps Application Onboarding Guide

## Simple GitOps Pattern

Follow the same pattern as existing apps (hojhon-site, vault). Everything is plain YAML manifests in Git.

## Application Structure

Each application follows this simple structure:
```
apps/[app-name]/
├── deployment.yaml        # Application deployment  
├── cloudflared.yaml      # Cloudflare tunnel (if web app)
└── other-resources.yaml # Any other K8s resources

homelab-apps/
└── [app-name]-app.yaml   # ArgoCD Application definition
```

## Onboarding New Applications

### Step 1: Copy Template
```bash
cp -r templates/web-app apps/my-new-app
```

### Step 2: Edit the YAML files
- Update `deployment.yaml`: Change image, app name, namespace
- Update `cloudflared.yaml`: Change hostname, tunnel name, service target  
- Update any other resource files

### Step 3: Create ArgoCD Application
Copy `templates/argocd-app.yaml` to `homelab-apps/my-new-app-app.yaml` and update:
- App name
- Namespace  
- Path reference

### Step 4: Commit to Git
```bash
git add apps/my-new-app homelab-apps/my-new-app-app.yaml
git commit -m "Add my-new-app"
git push
```

ArgoCD automatically detects and deploys!
- **Container ports**: Use 8080 for HTTP, 8443 for HTTPS (non-root)
- **Service ports**: Expose 80/443 externally, forward to container ports
- **Health checks**: Always configure readiness and liveness probes

## Security Best Practices
- Run containers as non-root users
- Use specific image tags, not `latest` in production
- Configure resource limits and requests
- Use `imagePullPolicy: Always` only for development

## Common Patterns

### Cloudflare Tunnel Configuration
```yaml
tunnel:
  existingSecret: [app-name]-cloudflared-cloudflare-tunnel-remote
  tokenKey: tunnelToken
  name: [tunnel-name]
ingress:
  - hostname: [domain.com]
    service: http://[service-name].[namespace].svc.cluster.local:80
  - service: http_status:404
```

### ArgoCD ignoreDifferences for Secrets
```yaml
ignoreDifferences:
  - group: ""
    kind: Secret
    name: [secret-name]
    jsonPointers:
      - /data/tunnelToken
      - /stringData/tunnelToken
```

## Troubleshooting
1. Check ArgoCD application sync status
2. Verify pod logs: `kubectl logs -n [namespace] [pod-name]`
3. Check service endpoints: `kubectl get endpoints -n [namespace]`
4. Test internal connectivity: `kubectl exec -it [pod] -- curl [service]`