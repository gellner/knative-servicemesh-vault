## Knative Functions

Configure registry, log in with push permissions:

```bash
export FUNC_REGISTRY=quay.io/gellner
podman login $FUNC_REGISTRY
```


Create an example Python function in the current directory:

```bash
kn func create -l python -t http pytest
```

View/Edit/Customise the function:

```bash
cd pytest
vi func.py
...
```

Test the function on the local machine (needs podman or docker)

```bash
$ kn func run --build
Building function image
🙌 Function built: quay.io/gellner/pytest:latest
Running on host port 8080
---> Running application from script (app.sh) ..
```

Check that function performs as expected by accessing localhost:8080
...


Deploy function onto OpenShift:

```bash
kn func deploy --namespace serverless-test-apps

# Or to avoid additional push for a demo:
kn func deploy --namespace serverless-test-apps --build=false --push=false

# Add the annotations necessary for Service mesh
oc patch service.serving.knative.dev pytest --type="merge" -p \
  '{"metadata": {"annotations": {"serving.knative.openshift.io/enablePassthrough":"true"}},"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/inject":"true","sidecar.istio.io/rewriteAppHTTPProbers":"true"}}}}}'

```

Alternatively, the `func.yaml` file can have the following added to ensure the annotations are included:

```yaml
deploy:
# ...
  annotations:
    serving.knative.openshift.io/enablePassthrough: "true"
    sidecar.istio.io/inject: "true"
    sidecar.istio.io/rewriteAppHTTPProbers: "true"
```

```bash
# Test the function:
kn func invoke --insecure

# (or use a web browser/curl etc...)
```