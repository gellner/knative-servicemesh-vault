# Create SA and Issuer for istio-csr

This configures an Issuer that targets the `pki/root/sign-intermediate` vault path and creates a intermediate CA cert specifically for istio to use when issuing service SPIFFE certs.

```bash
oc new-project istio-system
oc apply -f yaml/020-istio-ca-and-issuer.yaml
```


# Install istio-csr

Create a secret containing the Root CA for the Vault PKI (generated during the `vault-pki-config.sh` script run)

```bash
oc create secret generic istio-root-ca --from-file ca.pem=./RH_Custom_CA.crt -n istio-system
```

Run a Helm install for the Istio Cert Manager Agent - `istio-csr`:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install istio-csr jetstack/cert-manager-istio-csr -n istio-system -f ./yaml/vault-istio-csr-helm-values.yaml
```


Once the istio-csr deployment is Ready, there should be a `istiod` certificate created and issued:

```bash
$ oc get Certificate -owide
NAME       READY   SECRET       ISSUER                      STATUS                                          AGE
istio-ca   True    istio-ca     istio-intermediate-issuer   Certificate is up to date and has not expired   5m39s
istiod     True    istiod-tls   istio-ca                    Certificate is up to date and has not expired   4m31s

$ oc get secret istiod-tls -owide
NAME         TYPE                DATA   AGE
istiod-tls   kubernetes.io/tls   3      88s

```
