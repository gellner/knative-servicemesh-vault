# Integrating Service Mesh 2, Hashicorp Vault and Knative Serverless

## Background
This appendix details the configuration that was put in place to test and demo the combination of OpenShift Serverless with Service Mesh, cert manager and HashiCorp Vault. The demo environment used OpenShift 4.18 running on AWS, and a test HashiCorp Vault running on the cluster itself.

The configuration should be reviewed and enhanced before any part of it is considered for use in real environments.

The procedure uses YAML and supporting files that are hosted on Github at https://github.com/gellner/knative-servicemesh-vault/ 

Detailed documentation can be found in the [Red Hat OpenShift Serverless docs](https://docs.redhat.com/en/documentation/red_hat_openshift_serverless/).

## Client workstation requirements
The client workstation that is used to perform the configuration should have the following installed:
- `oc` - OpenShift CLI Client - can be downloaded from the cluster itself (`https://<webconsoleui>/command-line-tools`) or from https://console.redhat.com/openshift/downloads
- `helm` - Helm 3 client - can be downloaded from the cluster or via procedures at https://helm.sh/docs/intro/install/ 
- `kn` - Knative CLI Client - can be downloaded from the cluster or from https://console.redhat.com/openshift/downloads or https://knative.dev/docs/client/install-kn/
- `func` - Knative Functions CLI/plugin - https://knative.dev/docs/functions/install-func/
- `vault` - HashiCorp Vault CLI - https://developer.hashicorp.com/vault/tutorials/get-started/install-binary
- `podman` - available natively on Linux, can be downloaded for Windows or Mac from https://podman-desktop.io/downloads

## Operator installation
The following operators should be installed:

- cert-manager Operator for Red Hat OpenShift - `cert-manager-operator`
- Red Hat OpenShift Serverless - `serverless-operator`
- Red Hat OpenShift Service Mesh 2 - `servicemeshoperator`
- If ServiceMesh UI is needed:
    - Kiali Operator - `kiali-ossm-redhat-operators`
    - Red Hat OpenShift distributed tracing platform - `jaeger-operator`

> [!NOTE]
> Service Mesh 3 is currently not supported by OpenShift Serverless as of June 2025

The operators can be installed using the OperatorHub section of the OpenShift web console with the default settings.

The actual configuration of the Operators will occur in later steps.

## Install HashiCorp Vault
If an existing HashiCorp Vault isn't available, a demo Vault can be installed onto the cluster using HashiCorp's Helm charts.

Connect to the OCP cluster using `oc login` and then (edit  `server.route.host` value so it reflects the actual cluster's \*.apps wildcard URL):
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
oc new-project vault

# If your OCP cluster has persistent storage and a default StorageClass set:
helm install vault hashicorp/vault \
--set "global.openshift=true" \
--set "server.image.repository=docker.io/hashicorp/vault" \
--set "injector.image.repository=docker.io/hashicorp/vault-k8s" \
--set "server.route.enabled=true" \
--set "server.route.host=vaultui.apps.cluster1.example.com" \
--set "server.route.tls.termination=edge"

# OR... If the cluster doesn't have persistent storage, install an ephemeral vault:
helm install vault hashicorp/vault \
--set "server.dev.enabled=true" \
--set "global.openshift=true" \
--set "server.image.repository=docker.io/hashicorp/vault" \
--set "injector.image.repository=docker.io/hashicorp/vault-k8s" \
--set "server.route.enabled=true" \
--set "server.route.host=vaultui.apps.cluster1.example.com" \
--set "server.route.tls.termination=edge"
```

Configure vault to run a PKI and provide permissions to Kubernetes service accounts:
```bash
mkdir pki-config; cd pki-config
wget https://github.com/gellner/knative-servicemesh-vault/raw/refs/heads/main/scripts/vault-pki-config.sh
wget https://github.com/gellner/knative-servicemesh-vault/raw/refs/heads/main/scripts/role-issuer-policy.hcl
chmod 700 ./vault-pki-config.sh
```

**IF** the cluster has a self-signed ingress certificate, it is necessary to download the CA file and configure it for use by the vault CLI command:
```bash
openssl s_client -showcerts console-openshift-console.apps.cluster1.example.com:443 2>/dev/null< /dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > self-signed-ca.pem
export VAULT_CAPATH="$(pwd)/self-signed-ca.pem"
```

Configure the vaultui route specified during the Vault install and then run the configure script:
```bash
export VAULT_ADDR=https://vaultui.apps.cluster1.example.com
oc project vault
./vault-pki-config.sh
# ...
```

The script creates CA certificate files (for the vault PKI) and an `init-keys.json` file which contains unseal key and a token to allow vault access.

## Configure Cert Manager
```bash
oc apply -f https://github.com/gellner/knative-servicemesh-vault/raw/refs/heads/main/yaml/015-cert-manager-config.yaml

# Wait 10 seconds then check for ClusterIssuer health
oc get ClusterIssuer -owide
NAME           READY   STATUS           AGE
vault-issuer   True    Vault verified   1m

```

## Create Secondary issuer and install Istio cert manager agent
This configures an Issuer that targets the `pki/root/sign-intermediate` vault path and creates a intermediate CA cert specifically for istio to use when issuing service SPIFFE certs.
```bash
oc new-project istio-system
oc apply -f https://raw.githubusercontent.com/gellner/knative-servicemesh-vault/refs/heads/main/yaml/020-istio-ca-and-issuer.yaml

oc get Issuer -owide
NAME                        READY   STATUS                AGE
istio-ca                    True    Signing CA verified   17s
istio-intermediate-issuer   True    Vault verified        17s
```

Create a secret containing the Root CA for the Vault PKI (generated during the `vault-pki-config.sh` script run), and then run a Helm install for the Istio Cert Manager Agent - `istio-csr`:
```bash
oc create secret generic istio-root-ca --from-file ca.pem=./RH_Custom_CA.crt -n istio-system

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install istio-csr jetstack/cert-manager-istio-csr -n istio-system -f https://github.com/gellner/knative-servicemesh-vault/raw/refs/heads/main/yaml/vault-istio-csr-helm-values.yaml
```
Once the `istio-csr` deployment is Ready, there should be a `istiod` certificate created and issued:
```bash
oc get Certificate -owide
NAME       READY   SECRET       ISSUER                      STATUS                                          AGE
istio-ca   True    istio-ca     istio-intermediate-issuer   Certificate is up to date and has not expired   5m39s
istiod     True    istiod-tls   istio-ca                    Certificate is up to date and has not expired   62s

$ oc get secret istiod-tls -owide
NAME         TYPE                DATA   AGE
istiod-tls   kubernetes.io/tls   3      88s
```

## Service Mesh configuration
Create a wildcard cert for the external ingress gateway, a ServiceMeshControlPlane and a ServiceMeshMemberRoll (which includes the namespaces `knative-serving` and `knative-eventing`), and external and local gateways:
```bash
oc apply -f https://github.com/gellner/knative-servicemesh-vault/raw/refs/heads/main/yaml/025-servicemesh-with-cm-and-kn.yaml
# May need to be run twice on a new cluster - the gateway.networking.istio.io CRD isn't created until the first ServiceMesh is created
```

> [!NOTE]
> If the cluster already has a signed certificate for its default ingress, it is likely that browser HSTS will make very difficult to use a new certificate from Vault (a private signer) in modern browsers, without putting in place a new DNS entry for the Istio Ingress gateway.

The easiest workaround for demo purposes is to use the default ingress' existing certificate for the external Ingress gateway... ONLY run this block if the \*.apps.cluster1.example.com endpoints have a properly signed cert, and you want to avoid HSTS issues:
```bash
# ONLY run  blockthis if the *.apps.cluster1.example.com endpoints have a properly signed cert, and you want to avoid HSTS issues!
oc get IngressController default -n openshift-ingress-operator -oyaml | grep -A 1 defaultCertificate
  defaultCertificate:
    name: cert-manager-ingress-cert # Ingress cert secret name may be different in your cluster

oc extract/secret cert-manager-ingress-cert -n openshift-ingress  # Ingress cert secret name may be different
oc delete Certificate wildcard-cert -n istio-system
oc delete Secret wildcard-cert -n istio-system
oc create secret tls wildcard-cert --cert=tls.crt --key=tls.key -n istio-system
```

## Knative serving config

Create a KnativeServing that uses Istio:

```bash
oc apply -f https://github.com/gellner/knative-servicemesh-vault/raw/refs/heads/main/yaml/030-knative-serving.yaml
```

## Deploy Knative serving test apps:

```bash
oc new-project serverless-test-apps
oc apply -f https://github.com/gellner/knative-servicemesh-vault/raw/refs/heads/main/yaml/045-knative-demo-app.yaml  # Prime number app that uses concurrency scaling
oc apply -f https://github.com/gellner/knative-servicemesh-vault/raw/refs/heads/main/yaml/046-knative-demo-app-hpa.yaml  # Prime number app that uses cpu HPA scaling
```

Once deployed, the new Knative Services for the apps can be found in the `serverless-test-apps` in the "Serverless ... Serving" section of the OpenShift Web Console.


## Testing Knative functions

Knative functions are a development method and CLI tool that allows container images to be easily built in various programming languages for microservices with the intention to run them on Knative.

By default, Knative Functions support the following languages and frameworks (but additional languages can be added using language packs):
- Node.js
- Python
- Go
- Quarkus
- Rust
- Spring Boot
- TypeScript

Detailed documentation (including development guides for Go, Quarkus, Node.js, TypeScript and Python) can be found in the ["Functions" section of the Red Hat OpenShift Serverless docs](https://docs.redhat.com/en/documentation/red_hat_openshift_serverless/1.36/html-single/functions/index).

Configure the path to an existing registry to hold the container images and log in with a user that has push permissions:  
```bash
export FUNC_REGISTRY=registry.example.com/username
podman login $FUNC_REGISTRY
```

Create an example Python function called `pytest` - it will create a new function directory which contains the example function plus other necessary files that control the building of the function container image:
```bash
kn func create -l python -t http pytest
# This is a python example/template that responds to http requests.
# Alternatively, `-t cloudevents` would produce an example function that responds to Events
# Alternatively, `-l go` would produce an example function in Golang
```

View/Edit/Customise the function to perform the necessary logic for this microservice function: 
```bash
cd pytest
vi func.py
# The example function simply return the content of URL parameters in its response as JSON
```

#### Test the example function on the local workstation
(runs in podman)

```bash
$ kn func run --build
Building function image
🙌 Function built: registry.example.com/username/pytest:latest
Running on host port 8080
---> Running application from script (app.sh) ..
```
At this point, `localhost:8080` can be accessed on the workstation in a web browser (or by running curl or the `invoke` sub-command in another shell) - the still-running `kn func run` command will show any logs from the container:
```bash
$ kn func invoke 
{"message": "Hello World"}
$ curl http://localhost:8080/?foo=bar
{"foo": "bar"}
```

#### Deploy the example function on to an OpenShift cluster

Although it is possible to use the new image to create your own Knative Serving Service on the OpenShift cluster, the `kn func` command can do this automatically.

However, it is necessary to specify additional annotations to ensure connectivity works with Service Mesh:
```bash
# in the pytest directory for the function
kn func deploy --namespace serverless-test-apps

# Add the annotations necessary for Service Mesh
oc patch service.serving.knative.dev pytest -n serverless-test-apps --type="merge" -p \
'{"metadata": {"annotations": {"serving.knative.openshift.io/enablePassthrough":"true"}},"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/inject":"true","sidecar.istio.io/rewriteAppHTTPProbers":"true"}}}}}'
```

Alternatively, the `func.yaml` file in the function's directory can have the following added to ensure the annotations are included during the build:
```yaml
deploy:
# ...
  annotations:
    serving.knative.openshift.io/enablePassthrough: "true"
    sidecar.istio.io/inject: "true"
    sidecar.istio.io/rewriteAppHTTPProbers: "true"
```

