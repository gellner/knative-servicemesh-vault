# Rough way to perform reset between different config attempts




````bash
oc delete project httpbin
oc delete -f ./yaml/025-servicemesh-with-cm-simple.yaml        # Or similar file
helm uninstall istio-csr -n istio-system 




# Uninstall operators HERE if needed

oc delete project istio-system knative-eventing knative-serving knative-serving-ingress openshift-serverless






```



```bash

## Before removing Cert Manager:
oc delete Certificate wildcard-certs -n getestproj
oc delete ClusterIssuer vault-issuer

```