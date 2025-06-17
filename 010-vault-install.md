# Install Hashicorp Vault for Demo purposes

- OCP cluster needs a default StorageClass configured
- Needs `vault` cli command and `helm` on the client
- Client needs to be logged in to the OCP cluster.


```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

oc new-project vault

helm install vault hashicorp/vault \
    --set "global.openshift=true"  \
    --set "server.image.repository=docker.io/hashicorp/vault" \
    --set "injector.image.repository=docker.io/hashicorp/vault-k8s" \
    --set "server.route.enabled=true" \
    --set "server.route.host=vaultui.apps.cluster1.example.com" \
    --set "server.route.tls.termination=edge"
```

- Ensure VAULT_ADDR env var is set to the vault route URL
- If cluster is self-signed, set VAULT_CAPATH env var to point to the CA file

Then run `vault-pki-config.sh` script to initialise and configure vault and the PKI engine, including auth roles:

```bash
$ cd scripts
$ export VAULT_ADDR=https://vaultui.apps.cluster1.example.com
$ export VAULT_CAPATH="/home/user/clusters/cluster1/ingress.pem"   ## ONLY if route is self-signed or signed by a private signer
$ ./vault-pki-config.sh
```

Note: Safeguard the `init-keys.json` file - it will be needed to login to vault or to unseal it after a restart of the cluster

It is now possible to look at the Vault WebUI, logging in via the Token value in the `root_token` field in the `init-keys.json` file.