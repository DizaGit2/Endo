#!/bin/sh
# P0a Vault init (dev mode): enable the Transit engine and create the dev KEK.
# Run by the `vault-init` one-shot service in docker-compose.yml.
set -e
export VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-root}"

# wait for vault dev server to accept connections
sleep 4
vault secrets enable transit || true
vault write -f transit/keys/lumen-dev-kek || true
echo "vault-init complete"
