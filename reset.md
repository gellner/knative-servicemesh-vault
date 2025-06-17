




````bash
oc delete project httpbin
oc delete -f servicemesh-with-cm-simple.yaml        # Or similar file
helm uninstall istio-csr -n istio-system 


oc delete Certificate wildcard-certs -n getestproj
oc delete ClusterIssuer vault-issuer

# Uninstall operators

oc delete project istio-system knative-eventing knative-serving knative-serving-ingress openshift-serverless
```