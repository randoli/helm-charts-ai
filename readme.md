# Randoli SRE Agent

## Prerequisites
1) Before installing the SRE agent, install the [Randoli agent](https://github.com/randoli/helm-charts)
2) Setup AWS Bedrock credentials in a secret named `randoli-sre-agent-secret` in the `randoli-agents` namespace. This secret must contain the AWS_ACCESS_KEY_ID, AWS_REGION and AWS_SECRET_ACCESS_KEY keys. Example:

```yaml
apiVersion: v1
data:
  AWS_ACCESS_KEY_ID: <YOUR_AWS_ACCESS_KEY_ID>
  AWS_REGION: <YOUR_AWS_REGION>
  AWS_SECRET_ACCESS_KEY: <YOUR_AWS_SECRET_ACCESS_KEY>
kind: Secret
metadata:
  name: randoli-sre-agent-secret
  namespace: randoli-agents
type: Opaque

```

## Installation
Add the repository
```
helm repo add randoli https://randoli.github.io/helm-charts-ai
```

Install the Helm Chart
```
helm install randoli-sre-agent randoli/randoli-agent -n randoli-agents --set enabledNamespaces='<namespace1\,namespace2>'
```

NOTE: replace <namespace1\,namespace2> with a list of namespaces which can be analyzed by the Randoli SRE agent, separated by a escaped comma.

## Further configuration

- To change the daily budget for the Bedrock calls, set the value of dailyBudgetUsd flag (value in American dollars). Example:

`helm upgrade randoli-sre-agent randoli/randoli-agent -n randoli-agents --set dailyBudgetUsd=30`

- For further configuration, check the [values.yaml](charts/sre-agent/values.yaml) file

## Troubleshooting
- If you see this log message: "The security token included in the request is invalid", check that the credentials are properly set and that they are exposed to the randoli-sre-agent pod as the following environment variables: AWS_ACCESS_KEY_ID, AWS_REGION and AWS_SECRET_ACCESS_KEY