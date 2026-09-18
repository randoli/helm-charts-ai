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
helm repo add randoli https://helm.randoli.io
```

Install the Helm Chart
```
helm install sre-agent randoli/sre-agent -n randoli-agents --set analysis.enabledNamespaces='<namespace1\,namespace2>'
```

NOTE: replace <namespace1\,namespace2> with a list of namespaces which can be analyzed by the Randoli SRE agent, separated by a escaped comma.

### Install together with the Randoli agent

The SRE agent is also bundled into the `randoli-agent` umbrella chart as an optional
dependency. When installed this way, all endpoint configuration (Prometheus, Loki, Tempo,
OTel collector, agent callback/Flight SQL URLs) is provided by the umbrella chart:

```
helm install randoli randoli/randoli-agent -n randoli-agents \
  --set sreAgent.enabled=true \
  --set sreAgent.analysis.enabledNamespaces='<namespace1\,namespace2>'
```

> The legacy repository URL `https://randoli.github.io/helm-charts-ai` is frozen at
> sre-agent 0.1.0 and no longer receives updates. Use `https://helm.randoli.io`.

## MCP servers

The chart installs four MCP servers by default. Each one reaches the agent through an
`MCPConfiguration` custom resource (CR), and its templates, CR and server notes are in
[charts/sre-agent/templates/mcp/](charts/sre-agent/templates/mcp/). The CRD is in
[charts/sre-agent/crds/](charts/sre-agent/crds/).

| Server | What the chart installs | Turn it off |
|---|---|---|
| Kubernetes | Deployment, Service, RBAC, and two CRs: a read-only one for the RCA agent, and one that can make changes for the runbook, periodic runbook and chat agents | `mcpServers.kubernetes.enabled=false`. It is also off when `global.openshift.enabled=true` |
| Prometheus | Deployment, Service and CR, when `observability.prometheusUrl` is set | `mcpServers.prometheus.enabled=false` |
| Loki | Deployment, Service and CR | `mcpServers.loki.enabled=false` |
| Tempo | Only the CR, which points at `<observability.tempoUrl>/api/mcp`. The chart that installs Tempo must turn that endpoint on | `mcpServers.tempo.enabled=false` |

Other MCP servers, such as GitHub, Atlassian (Jira and Confluence), Argo CD, Strimzi and Kyverno,
are not part of this chart. Their manifests and CRs live in the `ai-agent` repo under `deploy/mcp/`.
Apply a server's manifests and CR from there, then restart the agent so it reads the new CR.

## Further configuration

- To change the daily budget for the Bedrock calls, set the value of analysis.dailyBudgetUsd flag (value in American dollars). Example:

`helm upgrade sre-agent randoli/sre-agent -n randoli-agents --set analysis.dailyBudgetUsd=30`

- **Standalone installs** (without the randoli-agent data plane chart): the defaults in the
  `observability` and `dataPlane` groups point at the data plane's service names, so override every
  endpoint there to match your own backends. Example:

```
helm upgrade sre-agent randoli/sre-agent -n randoli-agents \
  --set observability.prometheusUrl=http://my-prometheus:9090 \
  --set observability.lokiUrl=http://my-loki:3100 \
  --set observability.tempoUrl=http://my-tempo:3200 \
  --set observability.otelExporterEndpoint=http://my-otel-collector:4317 \
  --set observability.traceLoopBaseUrl=http://my-otel-collector:4318 \
  --set dataPlane.agentCallbackUrl=http://my-agent:8080/ \
  --set dataPlane.flightSqlUrl=grpc+tcp://my-agent:31337
```

- For further configuration, check the [values.yaml](charts/sre-agent/values.yaml) file

## Troubleshooting
- If you see this log message: "The security token included in the request is invalid", check that the credentials are properly set and that they are exposed to the randoli-sre-agent pod as the following environment variables: AWS_ACCESS_KEY_ID, AWS_REGION and AWS_SECRET_ACCESS_KEY
