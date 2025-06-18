# Configure a Service Mesh to use with Serverless


Create a wildcard cert for the external ingress gateway, a ServiceMeshControlPlane and a ServiceMeshMemberRoll (which includes the namespaces `knative-serving` and `knative-eventing`), and external and local gateways:

```bash
oc apply -f ./yaml/025-servicemesh-with-cm-and-kn.yaml
# May need to be run twice on a new cluster - the gateway.networking.istio.io CRD isn't created until the first ServiceMesh is created
```


Note: If the cluster already has a signed certificate for its default ingress, it is likely that browser HSTS will make very difficult to use a new certificate from Vault (a private signer) in modern browsers, without putting in place a new DNS entry for the Istio Ingress gateway.

The easiest workaround is to use the default ingress' certificate for the external Ingress gateway... eg:

```bash
oc extract/secret cert-manager-ingress-cert -n openshift-ingress

oc delete Certificate wildcard-cert -n istio-system
oc delete Secret wildcard-cert -n istio-system

oc create secret tls wildcard-cert --cert=tls.crt --key=tls.key -n istio-system

```

