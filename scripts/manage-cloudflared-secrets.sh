#!/usr/bin/env bash
# manage-cloudflared-secrets.sh
# Safely create/update cloudflared tunnel secrets for argocd (cloudflare ns)
# and hojhon-site. Also provides a check-only mode.
# Usage:
#  - Interactive: ./manage-cloudflared-secrets.sh
#  - Non-interactive: CF_TOKEN="<token>" ./manage-cloudflared-secrets.sh
#  - Check only: ./manage-cloudflared-secrets.sh --check

set -euo pipefail

NAMESPACE_CF=cloudflare
SECRET_CF=cloudflared-argocd-tunnel-secret
NAMESPACE_SITE=hojhon-site
SECRET_SITE=hojhon-cloudflared-cloudflare-tunnel-remote

usage() {
  cat <<EOF
Usage: $0 [--check]

Options:
  --check      Only check secrets and report empty/missing tokens

Environment:
  CF_TOKEN     (optional) the Cloudflare tunnel token. If not set, the script will prompt for it (masked).

Examples:
  CF_TOKEN=xxxxx $0            # create/update secrets non-interactively (uses same token for both)
  CF_TOKEN_CF=aaa CF_TOKEN_SITE=bbb $0  # provide separate tokens non-interactively
  $0                          # will prompt for token interactively
  $0 --check                  # only validate secrecy state
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
  echo "Checking cloudflared secrets..."
  for ns in "$NAMESPACE_CF" "$NAMESPACE_SITE"; do
    secret="$SECRET_SITE"
    if [ "$ns" = "$NAMESPACE_CF" ]; then
      secret="$SECRET_CF"
    fi
    if kubectl -n "$ns" get secret "$secret" >/dev/null 2>&1; then
      len=$(kubectl -n "$ns" get secret "$secret" -o jsonpath='{.data.tunnelToken}' 2>/dev/null || echo -n "" | true)
      if [ -z "$len" ]; then
        echo "MISSING or EMPTY token in $ns/$secret"
      else
        # print decoded byte-length
        b64=$(kubectl -n "$ns" get secret "$secret" -o jsonpath='{.data.tunnelToken}')
        bytes=$(echo -n "$b64" | base64 --decode | wc -c || true)
        echo "OK $ns/$secret length=$bytes"
      fi
    else
      echo "Secret not found: $ns/$secret"
    fi
  done
}

if [ "$check_only" = true ]; then
  check_secrets
  exit 0
fi

# Acquire tokens: support separate tokens for cloudflare (argocd) and site
# Backwards-compatible: CF_TOKEN can still be used for both if provided.
CF_TOKEN_CF=${CF_TOKEN_CF:-${CF_TOKEN:-}}
CF_TOKEN_SITE=${CF_TOKEN_SITE:-${CF_TOKEN:-}}

# prompt interactively for any missing tokens (only if running in tty)
prompt_for_token() {
  varname="$1"; prompt="$2"
  # use indirect expansion to check
  if [ -n "${!varname:-}" ]; then
    return 0
  fi
  if [ -t 0 ]; then
    printf "%s" "$prompt"
    IFS= read -r -s val
    printf "\n"
    eval "$varname=\"$val\""
  fi
}

prompt_for_token CF_TOKEN_CF "Enter Cloudflare (argocd) tunnel token (leave empty to skip): "
prompt_for_token CF_TOKEN_SITE "Enter Hojhon-site tunnel token (leave empty to skip): "

# prepare temp files only for tokens provided
TMPFILES=()
mk_tmpfile_from_var() {
  varname="$1"; outvar="$2"
  val=${!varname:-}
  if [ -n "$val" ]; then
    tf=$(mktemp)
    printf '%s' "$val" > "$tf"
    chmod 600 "$tf"
    TMPFILES+=("$tf")
    eval "$outvar=\"$tf\""
  else
    eval "$outvar=\"\""
  fi
}

mk_tmpfile_from_var CF_TOKEN_CF TMP_CF
mk_tmpfile_from_var CF_TOKEN_SITE TMP_SITE

trap 'for f in "${TMPFILES[@]:-}"; do rm -f "$f"; done' EXIT

# create/update secrets using --from-file to avoid shell quoting issues
if [ -n "$TMP_CF" ]; then
  echo "Creating/updating secret: $NAMESPACE_CF/$SECRET_CF"
  kubectl -n "$NAMESPACE_CF" create secret generic "$SECRET_CF" \
    --from-file=tunnelToken="$TMP_CF" --dry-run=client -o yaml | kubectl apply -f -
else
  echo "Skipping $NAMESPACE_CF/$SECRET_CF: no token provided"
fi

if [ -n "$TMP_SITE" ]; then
  echo "Creating/updating secret: $NAMESPACE_SITE/$SECRET_SITE"
  kubectl -n "$NAMESPACE_SITE" create secret generic "$SECRET_SITE" \
    --from-file=tunnelToken="$TMP_SITE" --dry-run=client -o yaml | kubectl apply -f -
else
  echo "Skipping $NAMESPACE_SITE/$SECRET_SITE: no token provided"
fi

# restart deployments so cloudflared picks up new secret
echo "Restarting cloudflared deployments (if present)"
kubectl -n "$NAMESPACE_CF" rollout restart deployment cloudflared-cloudflare-tunnel-remote --timeout=60s || true
kubectl -n "$NAMESPACE_SITE" rollout restart deployment hojhon-cloudflared-cloudflare-tunnel-remote --timeout=60s || true

# verify secrets and pods
echo "Verification:"
kubectl -n "$NAMESPACE_CF" get secret "$SECRET_CF" -o yaml || true
kubectl -n "$NAMESPACE_SITE" get secret "$SECRET_SITE" -o yaml || true

echo "Pods (cloudflared):"
kubectl -n "$NAMESPACE_CF" get pods -l app.kubernetes.io/name=cloudflare-tunnel-remote -o wide || kubectl -n "$NAMESPACE_CF" get pods --selector=app.kubernetes.io/instance=cloudflared -o wide || true
kubectl -n "$NAMESPACE_SITE" get pods -l pod=cloudflared -o wide || kubectl -n "$NAMESPACE_SITE" get pods --selector=app.kubernetes.io/instance=hojhon-cloudflared -o wide || true

# show decoded lengths
echo "Decoded token lengths:"
echo -n "cloudflare/ $SECRET_CF: "; kubectl -n "$NAMESPACE_CF" get secret "$SECRET_CF" -o jsonpath='{.data.tunnelToken}' | base64 --decode | wc -c || true
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

# Try to ensure the name for cloudflare and site deployments
ensure_tunnel_name "$NAMESPACE_CF" cloudflared-cloudflare-tunnel-remote homelab || true
ensure_tunnel_name "$NAMESPACE_SITE" hojhon-cloudflared-cloudflare-tunnel-remote hojhon-site || true
