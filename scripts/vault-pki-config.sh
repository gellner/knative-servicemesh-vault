#!/bin/bash

## Need to ensure vault is initialized and unsealed first...

# export VAULT_ADDR=https://vaultui.apps.cluster1.example.com
# export VAULT_CAPATH="/home/user/clusters/cluster1/ingress.pem"   ## ONLY if route is self-signed

# Command to initialize Vault
echo "Initializing Vault"
oc exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > init-keys.json

# Set environmental variables for unseal key and root token
echo "Setting environmental variables for the Unseal Key and the Root Token"
export VAULT_UNSEAL_KEY=$(cat init-keys.json | jq -r ".unseal_keys_b64[]")
export VAULT_ROOT_TOKEN=$(cat init-keys.json | jq -r ".root_token")
echo "VAULT_UNSEAL_KEY = $VAULT_UNSEAL_KEY"
echo "VAULT_ROOT_TOKEN = $VAULT_ROOT_TOKEN"


oc exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY

sleep 5


vault login $VAULT_ROOT_TOKEN

# --------------------------------------------------------------------------------------------------------------

### Enable the PKI engine #####
# Enable pki and set the default path -'pki' the path can be anythings for e.g. vault secrets enable -path=my_own_pki pki
# This basically creates a PKI enginge under the path pki
vault secrets enable -path=pki pki

# Tuning the max time / lease / expiry time of CA to 10 years (87600h)
vault secrets tune -max-lease-ttl=87600h pki

#############################

# --------------------------------------------------------------------------------------------------------------

### Create ROOT CA #####
# Configure the Root CA - This will generate a self-signed CA cert and private key. Note if the path ends with exported the private key will be returned in 
# the response. if it is internal the private key will not be returned and cannot be retrieved later. We use interanl and save the private key to have a copy
# --> max_path_length is set to 1 because we only have a 2 layer PKI and the last layer in our PKI setup, the Intermediates CA, will be 0
# --> key_bits: This will be the level of encryption. Vault default for PKI is 2048 but we will change this to be higher: 4096
# --> issuer_name: Name to that can be used as a reference to create a CSR as multiple issuers can be created. a default cert will be created if this field is omitted
vault write -field=certificate pki/root/generate/internal \
  max_path_length=1 \
  common_name="RH Custom Root CA" \
  ou="RH-FSI" \
  organization="Red Hat Consulting" \
  country="US" \
  ttl=87600h \
  issuer_name="rh-custom-root-ca" \
  key_bits=4096 > RH_Custom_CA.crt

# Configure the URLs - for downloading issuing certificates for the root ca and the CRL which is the certificate revocation list.
vault write pki/config/urls \
  issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
  crl_distribution_points="$VAULT_ADDR/v1/pki/crl"

# The following two commands are optional. It will configure the CRL expiry and rotate them
vault write pki/config/crl expiry="4380h"
vault read pki/crl/rotate
#############################

# --------------------------------------------------------------------------------------------------------------

### Create Intermediate CA #####
# Refer to the comments above for descriptions of these commands below
vault secrets enable -path=pki_int_ca pki
vault secrets tune -max-lease-ttl=43800h pki_int_ca # Setting the expire to 5 yrs

# --> max_path_length is equal to 0. This is to signal that this is the last level in our PKI and no more intermediates will follow. 
# Meaning that the certificates this Ca generates will be for End Entity (EE) users
vault write -format=json pki_int_ca/intermediate/generate/internal \
  require_cn=false \
  max_path_length=0 \
  common_name="RH Custom Intermediate CA" \
  ou="RH-FSI" \
  organization="Red Hat Consulting" \
  country="US" \
  issuer_name="rh-custom-intermediate-ca" \
  key_bits=4096 | jq -r '.data.csr' > RH_Custom_Intermediate_CA.csr

# We use the csr above to create a new intermediate CA cert. Here though we have configured the same values for CN, ou, Orgnaization, Country and Key_bits,
# it is not necessary to do so and we can also replace all those with "use_csr_values=true"
# We pass the csr file create above locally using the '@' character and then provide the file format
vault write -format=json pki/root/sign-intermediate \
  max_path_length=0 \
  common_name="RH Custom Intermediate CA" \
  ou="RH-FSI" \
  organization="Red Hat Consulting" \
  country="US" \
  ttl=43800h \
  key_bits=4096 \
  format=pem_bundle \
  issuer_ref="rh-custom-root-ca" \
  csr=@RH_Custom_Intermediate_CA.csr | jq -r '.data.certificate' > RH_Custom_Intermediate_CA.pem


# Once the CSR is signed and the root CA returns a certificate, it can be imported back into Vault.
vault write pki_int_ca/intermediate/set-signed certificate=@RH_Custom_Intermediate_CA.pem

vault write pki_int_ca/config/urls \
  issuing_certificates="$VAULT_ADDR/v1/pki_int_ca/ca" \
  crl_distribution_points="$VAULT_ADDR/v1/pki_int_ca/crl"

vault write pki_int_ca/config/crl expiry="4380h"
vault read pki_int_ca/crl/rotate

#############################

# --------------------------------------------------------------------------------------------------------------

### Create The Role #####
# We will now create the Role which will utilize the Intermediate CA to issue the End Entity (EE) or workload certs
# We create a role called 'rh-custom-issuer' which will issue certs using pki_int_ca.
# --> allow_any_name=True : Specifies if clients can request any CN. Useful in some circumstances. If you are using it for production you will want to have this to False and provide a specific value.
# --> allow_subdomains=true : This would allow hunter.example.com to be allowed, that is if example.com is in the allowed list. Which because of allow_any_name=True this is allowed.
# --> use_csr_common_name=true : This will use the CSR common name when you are signing a CSR.
# vault write pki_int_ca/roles/rh-custom-issuer  \
#   allow_any_name=true \
#   allow_uri_sans=true \
#   allow_ip_sans=true \
#   ou="RH-SPPRT" \
#   organization="Red Hat Consulting" \
#   country="US" \
#   use_csr_common_name=true \
#   ttl="4380h" \
#   max_ttl="4380h" \
#   key_type=any \
#   enforce_hostnames=false \
#   allow_bare_domains=true \
#   require_cn=false \
#   allowed_uri_sans="istio-system.svc, apps.pug50.co.uk, pug50.co.uk, cluster.local, spiffe://*" \
#   allow_subdomains=true 


vault write pki_int_ca/roles/rh-custom-issuer  \
  allow_any_name=true \
  allow_uri_sans=true \
  allow_ip_sans=true \
  ou="RH-SPPRT" \
  organization="Red Hat Consulting" \
  country="US" \
  use_csr_common_name=true \
  ttl="4380h" \
  max_ttl="4380h" \
  key_type=any \
  enforce_hostnames=false \
  allow_bare_domains=true \
  require_cn=false \
  allowed_uri_sans="*, spiffe://*" \
  allow_subdomains=true 

#############################

# Create a vault policy for the above created vault PKI role
vault policy write rh-custom-issuer_pki ./role-issuer-policy.hcl

# --------------------------------------------------------------------------------------------------------------


### Create The App Role that will be used to authenticate with Vault server #####
vault auth enable approle

# Create a vault policy for the above created vault PKI role
vault policy write approle_policy ./role-issuer-policy.hcl


# Enable Kubernetes authentication
vault auth enable kubernetes

# Create a vault policy for the above created vault PKI role
vault policy write k8s_policy/role-issuer-policy.hcl

# --> secret_id_ttl=10m: Duration in either an integer number of seconds (3600) or an integer time unit (60m) after which by default any SecretID expires. A value of zero will allow the SecretID to not expire. However, this option may be overridden by the request's 'ttl' field when generating a SecretID.
# --> token_num_uses=10: The maximum number of times a generated token may be used (within its lifetime); 0 means unlimited. If you require the token to have the ability to create child tokens, you will need to set this value to 0
# --> token_ttl=10m: The incremental lifetime for generated tokens. This current value of this will be referenced at renewal time
# --> token_max_ttl=15m: The maximum lifetime for generated tokens. This current value of this will be referenced at renewal time
# --> secret_id_num_uses=0: Number of times any particular SecretID can be used to fetch a token from this AppRole, after which the SecretID by default will expire. A value of zero will allow unlimited uses. However, this option may be overridden by the request's 'num_uses' field when generating a SecretID.
vault write auth/approle/role/rh-vault-pki-role \
    secret_id_ttl=0 \
    token_num_uses=10 \
    token_ttl=10m \
    token_max_ttl=15m \
    secret_id_num_uses=0 \
    policies=approle_policy \
    policies=k8s_policy

# Set Kuberntes API endpoint
vault write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc.cluster.local"

# This part was confusing as the preferred method changed.  This below command is connecting a service account to the PKI policy
# Cert manager docs here - https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-cert-manager
# Info on the service account here - https://developer.hashicorp.com/vault/docs/auth/kubernetes#discovering-the-service-account-issuer
# Based on these two documents together, what's being bound is the default service account in the vault namespace

# The issuer service account needs to be placed in the cert-manager namespace so that the cert-manager ClusterIssuer has the proper access
vault write auth/kubernetes/role/issuer bound_service_account_names=issuer bound_service_account_namespaces=cert-manager bound_service_account_namespaces=istio-system policies=k8s_policy ttl=87600h