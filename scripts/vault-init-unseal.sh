#!/usr/bin/env bash
set -euo pipefail

# Safe helper to initialize and unseal Vault running in the 'vault' namespace.
# - Streams the `vault operator init` output to a local file (default: $HOME/vault-init.json)
# - Extracts the single unseal key locally and runs `vault operator unseal` inside the pod
# - Writes a sanitized copy (no secrets) to $HOME/vault-init.sanitized.json
#
# Usage: ./scripts/vault-init-unseal.sh [--out /path/to/vault-init.json] [--force]

OUTFILE="${HOME}/vault-init.json"
SANITIZED="${HOME}/vault-init.sanitized.json"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUTFILE="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help)
      sed -n '1,120p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -e "$OUTFILE" && $FORCE -ne 1 ]]; then
  echo "Refusing to overwrite existing $OUTFILE. Use --force to override." >&2
  exit 1
fi

echo "Locating Vault pod in namespace 'vault'..."
POD=$(kubectl -n vault get pod -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$POD" ]]; then
  echo "No vault pod found in namespace 'vault'" >&2
  exit 2
fi
echo "Found pod: $POD"

echo "Running 'vault operator init' inside pod and streaming to $OUTFILE (will contain keys; keep it secret)"
kubectl -n vault exec -i "$POD" -- vault operator init -key-shares=1 -key-threshold=1 -format=json > "$OUTFILE"
chmod 600 "$OUTFILE"
echo "Wrote init JSON to $OUTFILE (chmod 600)."

if ! command -v jq >/dev/null 2>&1; then
  echo "Warning: 'jq' not found locally. Install jq to allow automatic unseal extraction and sanitization." >&2
  echo "You can manually extract the unseal key with: jq -r '.unseal_keys_b64[0]' $OUTFILE" >&2
  exit 0
fi

echo "Extracting unseal key locally (not printing it) and performing unseal..."
UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$OUTFILE")
kubectl -n vault exec -i "$POD" -- vault operator unseal "$UNSEAL_KEY"

echo "Unseal command sent. Verifying Vault status..."
kubectl -n vault exec -it "$POD" -- vault status -format=json | jq .

echo "Creating a sanitized copy without secrets at $SANITIZED"
jq 'del(.unseal_keys_b64, .root_token)' "$OUTFILE" > "$SANITIZED" && chmod 600 "$SANITIZED"
echo "Sanitized JSON written to $SANITIZED (safe to paste here for verification)."

echo "Done. Keep $OUTFILE and any extracted tokens secure. Do NOT paste them into chat or public locations."
