# Deploy test Serverless Apps


```bash
oc new-project client
oc new-project httpbin
oc new-project serverless-test-apps


oc apply -f ./yaml/040-knative-test-apps.yaml

```