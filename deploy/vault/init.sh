#!/bin/sh
# Vault init (dev mode): enable the Transit engine and create the dev KEK + email-HMAC keys.
# Run by the `vault-init` one-shot service in docker-compose.yml — the single init path (P3c-T3).
# Idempotent: safe to re-run against an already-initialized dev Vault.
set -e
export VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-root}"

# wait for the vault dev server to accept connections
until vault status >/dev/null 2>&1; do
  echo "waiting for vault..."
  sleep 1
done

vault secrets enable transit || true
vault write -f transit/keys/lumen-dev-kek || true
vault write -f transit/keys/lumen-dev-email-hmac || true
echo "vault-init complete"
