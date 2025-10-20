#!/usr/bin/env bash
# manage-cloudflared-secrets.sh
# Safely create/update cloudflared tunnel secrets for hojhon-site only.
# ArgoCD now uses internal DNS instead of Cloudflare tunnels.
# Usage:
#  - Interactive: ./manage-cloudflared-secrets.sh
#  - Non-interactive: CF_TOKEN="<token>" ./manage-cloudflared-secrets.sh
#  - Check only: ./manage-cloudflared-secrets.sh --check

set -euo pipefail

NAMESPACE_SITE=hojhon-site
SECRET_SITE=hojhon-cloudflared-cloudflare-tunnel-remote

usage() {
  cat <<EOF
Usage: $0 [--check]

Options:
  --check      Only check secrets and report empty/missing tokens

Environment:
  CF_TOKEN     The Cloudflare tunnel token for hojhon-site. If not set, the script will prompt for it (masked).

Examples:
  CF_TOKEN=xxxxx $0            # create/update secret non-interactively
  $0                          # will prompt for token interactively
  $0 --check                  # only validate secret state
EOF
}

check_only=false

while [[ ${1:-} != "" ]]; do
  case "$1" in
    --check) check_only=true ;; 
    --vault) create_vault=true ;; 
    -h|--help) usage; exit 0 ;; 
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
  shift
done

# helper: check that kubectl is installed
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found in PATH" >&2
  exit 2
fi

check_secrets() {
  echo "Checking cloudflared secret for hojhon-site..."
  if kubectl -n "$NAMESPACE_SITE" get secret "$SECRET_SITE" >/dev/null 2>&1; then
    len=$(kubectl -n "$NAMESPACE_SITE" get secret "$SECRET_SITE" -o jsonpath='{.data.tunnelToken}' 2>/dev/null || echo -n "" | true)
    if [ -z "$len" ]; then
      echo "MISSING or EMPTY token in $NAMESPACE_SITE/$SECRET_SITE"
    else
      # print decoded byte-length
      b64=$(kubectl -n "$NAMESPACE_SITE" get secret "$SECRET_SITE" -o jsonpath='{.data.tunnelToken}')
      bytes=$(echo -n "$b64" | base64 --decode | wc -c || true)
      echo "OK $NAMESPACE_SITE/$SECRET_SITE length=$bytes"
    fi
  else
    echo "Secret not found: $NAMESPACE_SITE/$SECRET_SITE"
  fi
}

if [ "$check_only" = true ]; then
  check_secrets
  exit 0
fi

# Acquire token for hojhon-site tunnel
CF_TOKEN_SITE=${CF_TOKEN:-}

# prompt interactively for missing token (only if running in tty)
if [ -z "$CF_TOKEN_SITE" ] && [ -t 0 ]; then
  printf "Enter Hojhon-site tunnel token: "
  IFS= read -r -s CF_TOKEN_SITE
  printf "\n"
fi

# prepare temp file for the token
TMPFILES=()
if [ -n "$CF_TOKEN_SITE" ]; then
  TMP_SITE=$(mktemp)
  printf '%s' "$CF_TOKEN_SITE" > "$TMP_SITE"
  chmod 600 "$TMP_SITE"
  TMPFILES+=("$TMP_SITE")
else
  TMP_SITE=""
fi

trap 'for f in "${TMPFILES[@]:-}"; do rm -f "$f"; done' EXIT

# create/update secret using --from-file to avoid shell quoting issues
if [ -n "$TMP_SITE" ]; then
  echo "Creating/updating secret: $NAMESPACE_SITE/$SECRET_SITE"
  kubectl -n "$NAMESPACE_SITE" create secret generic "$SECRET_SITE" \
    --from-file=tunnelToken="$TMP_SITE" --dry-run=client -o yaml | kubectl apply -f -
else
  echo "No token provided for $NAMESPACE_SITE/$SECRET_SITE"
  exit 1
fi

# restart deployment so cloudflared picks up new secret
echo "Restarting hojhon-site cloudflared deployment"
kubectl -n "$NAMESPACE_SITE" rollout restart deployment hojhon-cloudflared-cloudflare-tunnel-remote --timeout=60s || true

# verify secret and pods
echo "Verification:"
kubectl -n "$NAMESPACE_SITE" get secret "$SECRET_SITE" -o yaml || true

echo "Pods (cloudflared):"
kubectl -n "$NAMESPACE_SITE" get pods -l pod=cloudflared -o wide || kubectl -n "$NAMESPACE_SITE" get pods --selector=app.kubernetes.io/instance=hojhon-cloudflared -o wide || true

# show decoded length
echo "Decoded token length:"
echo -n "hojhon-site/ $SECRET_SITE: "; kubectl -n "$NAMESPACE_SITE" get secret "$SECRET_SITE" -o jsonpath='{.data.tunnelToken}' | base64 --decode | wc -c || true

echo "Done. If ArgoCD re-applies an empty secret from Git, consider using SealedSecrets, ExternalSecrets, or a CI step to inject the secret instead of committing empty secrets to the repo."

# Ensure deployment command contains the tunnel name as last argument. Some chart versions
# require the tunnel name to be passed explicitly to `cloudflared tunnel run <name>`.
ensure_tunnel_name() {
  ns="$1"; dep="$2"; tname="$3"
  # read existing command array (space-separated)
  cmd=$(kubectl -n "$ns" get deployment "$dep" -o jsonpath='{.spec.template.spec.containers[0].command[*]}' 2>/dev/null || true)
  if [ -z "$cmd" ]; then
    echo "Deployment $ns/$dep not found or has no command; skipping ensure_tunnel_name"
    return 0
  fi
  # check whether last element equals the tunnel name
  last=$(echo "$cmd" | awk '{print $NF}')
  if [ "$last" = "$tname" ]; then
    echo "Deployment $ns/$dep already includes tunnel name '$tname'"
    return 0
  fi
  echo "Patching deployment $ns/$dep to append tunnel name '$tname' to command"
  kubectl -n "$ns" patch deployment "$dep" --type='json' -p "[{
    \"op\": \"add\", 
    \"path\": \"/spec/template/spec/containers/0/command/-\",
    \"value\": \"$tname\"
  }]"
  echo "Waiting for rollout to finish for $ns/$dep"
  kubectl -n "$ns" rollout status deployment "$dep" --timeout=120s || true
}

# Ensure the tunnel name for hojhon-site deployment only
ensure_tunnel_name "$NAMESPACE_SITE" hojhon-cloudflared-cloudflare-tunnel-remote hojhon-site || true
