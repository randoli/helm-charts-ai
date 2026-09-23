# Randoli SRE Agent

.

## Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
  - [Install together with the Randoli agent](#install-together-with-the-randoli-agent)
- [MCP servers](#mcp-servers)
- [What an MCPConfiguration says, and what the agent does with it](#what-an-mcpconfiguration-says-and-what-the-agent-does-with-it)
  - [spec.tools: the allow list and what each tool does](#spectools-the-allow-list-and-what-each-tool-does)
  - [spec.sensitiveTools: tools whose output is credentials](#specsensitivetools-tools-whose-output-is-credentials)
  - [After changing a CR](#after-changing-a-cr)
- [Choosing the models](#choosing-the-models)
  - [The LLM provider](#the-llm-provider)
  - [The pricing file, and what a model can do](#the-pricing-file-and-what-a-model-can-do)
  - [One model per role](#one-model-per-role)
- [Further configuration](#further-configuration)
- [Troubleshooting](#troubleshooting)

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

## What an MCPConfiguration says, and what the agent does with it

A CR is the whole contract for one MCP server: which agents get it, where it is, what it may be used
for, which of its tools may be called, which of those change things, and which of them return
credentials. Nothing about a server is decided in the agent's code, so adding a server or changing
what it may do is a `kubectl apply` and a restart.

```yaml
apiVersion: mcp.ai.randoli.io/v1beta1
kind: MCPConfiguration
metadata:
  name: mcp-kubernetes
  annotations:
    mcp.ai.randoli.io/runbook:  "enabled"
    mcp.ai.randoli.io/sre-chat: "enabled"
spec:
  type: kubernetes
  transport: streamable_http
  url: http://randoli-mcp-server-kubernetes.randoli-agents.svc:8080/mcp
  tools:
    pods_list:       read
    pods_get:        read
    pods_log:        read
    resources_get:   read
    pods_delete:     mutate
    resources_scale: mutate
  sensitiveTools: []
  prompt: |
    ## Kubernetes server notes
    Scope: the live state of this cluster through the Kubernetes API ...
```

| Field | Required | What the agent does with it |
|---|---|---|
| `metadata.annotations` | yes, at least one | Decides which agents get this server. The key is `mcp.ai.randoli.io/<agent>`, for `rca`, `runbook`, `periodic-runbook`, `runbook-validation` or `sre-chat`, and the value must be the string `"enabled"`. An agent that is not annotated never sees the server |
| `spec.type` | yes | The family. For `kubernetes`, `openshift`, `prometheus`, `loki` and `tempo` the server **replaces** the agent's own tools for that family; any other value is **additive**, so the server's tools are added alongside. One type may be enabled once per agent, and a second CR claiming the same type for the same agent is a configuration error the agent reports at startup rather than picking one silently |
| `spec.transport` | yes | `streamable_http` or `sse` |
| `spec.url` | yes | Where the server is. In-cluster Service URLs are what the chart uses |
| `spec.prompt` | yes | The server's own notes, put into the agent's system prompt as written, after the agent's core rules. This is where a server says what it is the source of truth for, which identifier keys which signal, its label names and query shapes, and its limits. It cannot loosen the agent's evidence or safety rules |
| `spec.tools` | in practice yes | The tools this server may expose, each marked `read` or `mutate`. See below |
| `spec.sensitiveTools` | no | Tools whose output is credentials. See below |
| `spec.headers` | no | Headers sent to the server. `${VAR}` is expanded from the pod's environment, so a token stays in a Kubernetes Secret and never in the CR |
| `spec.category` | no | A free label. Only `ticketing` is read today, so the runbook agent can find whichever ticketing server is connected without knowing its type |
| `spec.allowedTools` | no | Deprecated, replaced by `spec.tools`. Still accepted so an older CR applies, but a server that has only this is not enabled |

### `spec.tools`: the allow list and what each tool does

The keys are the allow list. A tool the map does not name is never given to any agent, however many
tools the server advertises. The value says what the tool does, and the agent acts on it:

| Value | What happens |
|---|---|
| `read` | The tool is bound and called freely |
| `mutate` | The tool is only bound for the agents that may change things, and **every call is refused until the user approves that exact call, arguments and all**. In the chat agent the user is shown what will be done, what the object looks like now and after, what else it touches and how to undo it, and their approval unlocks that one call and no other. The read-only agents, which are RCA, periodic runbook and runbook validation, are never given the tool, and in eval mode no agent may call it |

Nothing is inferred from a tool's name. A tool named `pods_evict` is a read unless the CR says
otherwise, which is why **a CR with no `spec.tools` is not enabled at all**: the agent logs an error
naming the CR and carries on without that server, because a change nobody put to the user is worse
than a server the agent does not have. A value other than `read` or `mutate` is rejected by the API
server, and a tool name the server does not advertise is logged and skipped.

### `spec.sensitiveTools`: tools whose output is credentials

Most servers need none of this, because three rules already apply to **every** server, declared or
not:

- a `Secret` anywhere in a result has its `data` and `stringData` values replaced, and its keys kept,
  so the agent can still say which keys exist and never sees one
- a value whose **key name** reads like a credential is replaced at any depth in any structured
  result, against `analysis.credentialKeyPattern`. That is what leaves a ConfigMap readable while
  the `DB_PASSWORD` inside it is not
- a credential **inside** a value is replaced wherever the value appears, structured or not: the
  password in a `scheme://user:password@host` address and one handed over in a query string. No key
  name betrays these - `MONGODB_URL` is a name worth reading - so only the credential goes and the
  host, port, database and query stay

Name a tool here only when neither rule can see its output: a secret store read that returns a bare
string, for instance. Then its result keeps its shape and key names with every value replaced, and a
result that cannot be parsed is withheld whole and the agent is told so, rather than being handed
something it could read as "nothing found".

All of this happens where the tool returns, so no summary, log line, audit row, ticket or stored
answer downstream ever holds a value.

### After changing a CR

Apply it and restart the agent, which reads the CRs at startup:

```
kubectl apply -f my-server-cr.yaml
kubectl rollout restart deployment/randoli-sre-agent -n randoli-agents
```

The startup log is the confirmation. Each server logs how many of its tools were kept, how many of
them change systems and their names, and how many return credentials; `mcp.init` names each server
per agent, and the toolset dump lists every tool the agent bound, tagged by origin.

## Choosing the models

### The LLM provider

`llm.provider` decides which vendor every call goes to. The chart defaults to AWS Bedrock, which is
what the Prerequisites secret above is for. Each provider reads its own credentials and needs its
own model ids, so switching one means setting both.

| `llm.provider` | Serves | Credentials it reads |
|---|---|---|
| `aws` (Bedrock) | anything on Bedrock, through the Converse API | `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| `anthropic` | the Anthropic API | `ANTHROPIC_API_KEY` |
| `openai` | the OpenAI API, or any endpoint that speaks it | `OPENAI_API_KEY`, and `OPENAI_BASE_URL` for anything that is not api.openai.com |
| `azure_openai` | Azure OpenAI deployments | `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY`, `OPENAI_API_VERSION` |
| `vertex` | Gemini, and Claude through Model Garden | `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`, and a service account |
| `azure_anthropic`, `azure_meta`, `azure_mistral`, `azure_deepseek` | the Azure AI Foundry `/models` route | the same three Azure values |

Put that provider's keys in the secret named by `llm.credentialsSecretName`, the same way the
Bedrock keys go in: the whole secret is loaded into the pod's environment, so whichever keys a
provider needs are the keys you put there. What each provider does differently - how it marks a
cached prompt, whether it takes a forced tool call, where its timeout goes - the agent handles, so
nothing beyond credentials and model ids changes per vendor.

The four Azure AI Foundry providers in the last row need the `langchain-azure-ai` package in the
agent image. If it is not there, the agent says so at startup and stops; the rest of the table
works with the image as shipped.

### The pricing file, and what a model can do

`models.yaml` is mounted from a ConfigMap this chart renders, and it is both the price list and the
allow list: a model that is not in it cannot be used, whatever the role keys say. Only the active
provider's entries are built, so the file can hold every provider at once.

```yaml
models:
  - provider: bedrock
    id: us.anthropic.claude-sonnet-4-5-20250929-v1:0
    input_cost:          0.0000033
    output_cost:         0.0000165
    cache_read_cost:     0.00000033
    cache_write_5m_cost: 0.000004125
    cache_write_1h_cost: 0.0000066
```

Costs are USD per token. Cache writes have two rates because the price depends on the lifetime set
by `llm.promptCacheTtl`, and which one applies is decided per call from what the provider reported.

Two optional flags per model cover the things that are not about price:

| Flag | Default | What it decides |
|---|---|---|
| `supports_prompt_cache` | whether any cache cost above is non-zero | whether this model is sent cache markers at all. A marker a model does not accept fails the whole call, so a model priced with no caching is simply never sent one |
| `supports_tool_choice` | `true` | whether the agent may force a tool call when it needs an answer in a fixed shape. Bedrock's Converse API only accepts this for some model families; set it to `false` for the rest and the agent asks instead of forcing, which still works |

### One model per role

Every step of an investigation resolves its model through a key in the `models` map, so the heavy
reasoning can use a strong model while summaries, per-iteration findings, compaction and chat titles
use a cheap one. The key name **is** the role name, per agent: `RCA_INVESTIGATOR_MODEL`,
`SRE_CHAT_EXECUTOR_MODEL`, `SRE_CHAT_TOOL_OUTPUT_SUMMARIZER_MODEL`, and so on. Each one becomes an
env var of the same name.

```
helm upgrade sre-agent randoli/sre-agent -n randoli-agents \
  --set llm.provider=anthropic \
  --set models.SRE_CHAT_EXECUTOR_MODEL=claude-sonnet-4-5-20250929 \
  --set models.SRE_CHAT_TOOL_OUTPUT_SUMMARIZER_MODEL=claude-haiku-4-5-20251001
```

Every id set there must also appear in `models.yaml` for the active provider. If one does not, the
agent says so in a single startup line naming every role that is wrong, which is what you want the
first time you change provider and half the keys still hold the old ids.

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

- **LLM call timeouts** are split in two, because the two kinds of call are nothing alike. A big
  reasoning call can legitimately run for minutes (`llm.readTimeoutSeconds`, 240s), while the small
  side calls - summaries, per-iteration findings, compaction, chat titles - never do
  (`llm.sideReadTimeoutSeconds`, 60s). The timeout is what a dead connection costs you, so raise the
  first one only if you see real calls being cut off, and leave the second one low.

- **Idle connections** get dropped by NAT gateways and VPC endpoints after about 350 seconds, and
  the agent only finds out when the next call hangs. So it makes one tiny call every
  `llm.keepWarmSeconds` (240s) to keep the pool alive. Set it to `'0'` if you would rather not.

- For further configuration, check the [values.yaml](charts/sre-agent/values.yaml) file

## Troubleshooting
- If you see this log message: "The security token included in the request is invalid", check that the credentials are properly set and that they are exposed to the randoli-sre-agent pod as the following environment variables: AWS_ACCESS_KEY_ID, AWS_REGION and AWS_SECRET_ACCESS_KEY
