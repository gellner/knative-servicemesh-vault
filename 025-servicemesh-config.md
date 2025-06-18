# Configure a Service Mesh to use with Serverless


Create a wildcard cert for the external ingress gateway, a ServiceMeshControlPlane and a ServiceMeshMemberRoll (which includes the namespaces `knative-serving` and `knative-eventing`), and external and local gateways:

```bash
oc apply -f ./yaml/025-servicemesh-with-cm-and-kn.yaml

```


