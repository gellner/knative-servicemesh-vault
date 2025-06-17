# Install Operators

We will need to install the following Operators:

- cert-manager Operator for Red Hat OpenShift - `cert-manager-operator`
- Red Hat OpenShift Serverless - `serverless-operator`
- Red Hat OpenShift Service Mesh 2 - `servicemeshoperator`
- If ServiceMesh UI is needed:
    - Kiali Operator - `kiali-ossm-redhat-operators`
    - Red Hat OpenShift distributed tracing platform - `jaeger-operator`

(NOTE: Service Mesh 3 is currently not supported with Serverless - June 2025)

The operators can be installed using the OperatorHub UI with the default settings.

The actual configuration of the Operators will occur in later steps.