#!/bin/bash

# Run this from the directory that contains the init-keys.json file, while logged into oc cli.

# Set environmental variables for unseal key and root token
echo "Setting environmental variables for the Unseal Key and the Root Token"
export VAULT_UNSEAL_KEY=$(cat init-keys.json | jq -r ".unseal_keys_b64[]")
export VAULT_ROOT_TOKEN=$(cat init-keys.json | jq -r ".root_token")
echo "VAULT_UNSEAL_KEY = $VAULT_UNSEAL_KEY"
echo "VAULT_ROOT_TOKEN = $VAULT_ROOT_TOKEN"


oc exec vault-0 -n vault -- vault operator unseal $VAULT_UNSEAL_KEY
