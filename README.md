# Randoli SRE Agent



## Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
  - [Install together with the Randoli agent](#install-together-with-the-randoli-agent)
- [MCP servers](#mcp-servers)
- [Guardrails](#guardrails)
- [What an MCPConfiguration says, and what the agent does with it](#what-an-mcpconfiguration-says-and-what-the-agent-does-with-it)
  - [spec.tools: the allow list and what each tool does](#spectools-the-allow-list-and-what-each-tool-does)
  - [spec.sensitiveTools: tools whose output is credentials](#specsensitivetools-tools-whose-output-is-credentials)
  - [After changing a CR](#after-changing-a-cr)
- [Choosing the models](#choosing-the-models)
  - [The LLM provider](#the-llm-provider)
  - [The pricing file, and what a model can do](#the-pricing-file-and-what-a-model-can-do)
  - [One model per role](#one-model-per-role)
  - [Thinking and temperature](#thinking-and-temperature)
- [Further configuration](#further-configuration)
- [Every setting](#every-setting)
  - [Credentials and the provider](#credentials-and-the-provider)
  - [Budget](#budget)
  - [Model calls](#model-calls)
  - [What an agent may investigate](#what-an-agent-may-investigate)
  - [Tool results and the context window](#tool-results-and-the-context-window)
  - [SRE chat](#sre-chat)
  - [MCP client](#mcp-client)
  - [Server and pools](#server-and-pools)
  - [Datastore](#datastore)
  - [Observability](#observability)
  - [Models and thinking](#models-and-thinking)
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

## Guardrails

The Kubernetes MCP server can delete pods and change replica counts. The chart stops it from doing
either to the workloads the agent itself runs on, so a chat or a runbook cannot take the agent down.

- Three ValidatingAdmissionPolicies refuse these requests when they come from the Kubernetes MCP
  server's service account, or the OpenShift server's (`mcp-server-openshift`): deleting a protected
  workload's pods or ReplicaSets, deleting or restarting the workload, and changing its replica
  count. `randoli-tproxy` may be scaled, but not below one replica. RBAC can only grant, never deny,
  so this cannot be a ClusterRole rule. The server's `pods_delete` deletes pods rather than evicting
  them, so Pod Disruption Budgets alone would not stop it either.
- The policies need Kubernetes 1.30 or later (OpenShift 4.17 or later). On older clusters the chart
  leaves them out, and the server notes do not mention them.
- A PodDisruptionBudget with `minAvailable: 1` for each protected workload keeps one replica up
  through voluntary disruptions such as node drains. With a single replica, a drain of the node that
  runs it cannot finish until someone moves the pod, which can stall a node upgrade. Pods that are
  not healthy can still be evicted.
- The agent reads these policies from the cluster when it starts, the same way it reads the MCP
  server's RBAC, and adds them to the Kubernetes server's notes with an explanation. Its prompts treat
  a change the policies refuse as one it never makes or asks approval for, whoever asks,
  administrators included, and however often; anyone who needs it makes it by hand. The agent's ClusterRole can read `validatingadmissionpolicies` and their bindings for this.
  A change to the policies reaches the agent when it restarts.

| Value | What it does |
|---|---|
| `guardrails.enabled` | Turns the policies and the budgets on or off |
| `guardrails.podDisruptionBudgets` | Turns the budgets on or off |
| `guardrails.serviceAccounts` | More service accounts held to the same rules, each a `name` and an optional `namespace` |
| `guardrails.workloads` | The protected workloads: `name`, `kind` (`Deployment` or `StatefulSet`), `matchLabels` of their pods, an optional `namespace`, and `allowScale: true` to allow scaling to one replica or more |

The default list is the Randoli agent (`randoli-agent`), its database (`randoli-fsqld`), the SRE
agent, `randoli-tproxy`, the MCP servers this chart installs, and the optional MCP servers from the
`ai-agent` repo.

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

Two numbers per model size each run: `context_window`, the tokens one call may hold, and
`max_output_tokens`, the most one reply may write. The agent compacts its history before it passes
`analysis.compactionTriggerPct` of the window, keeping the newest replies word for word up to
`analysis.compactionKeepRecentPct` of it. A tool result reaches the model whole unless it is over
the window limit: `analysis.toolResultMaxWindowPct` of the window (15%), and at most
`analysis.toolResultMaxTokens` tokens (25,000). A longer result is saved to a file in the pod and
reaches the model with a large preview, and the model reads the rest with a read-only `bash` tool,
whose own large reads are saved the same way. A model without these
two numbers gets 200,000 and 16,000.

Two optional flags per model cover the things that are not about price:

| Flag | Default | What it decides |
|---|---|---|
| `supports_prompt_cache` | whether any cache cost above is non-zero | whether this model is sent cache markers at all. A marker a model does not accept fails the whole call, so a model priced with no caching is simply never sent one |
| `supports_tool_choice` | `true` | whether the agent may force a tool call when it needs an answer in a fixed shape. Bedrock's Converse API only accepts this for some model families; set it to `false` for the rest and the agent asks instead of forcing, which still works |

### One model per role

Each agent runs its loop on one model, named by a key in the `models` map: `RCA_INVESTIGATOR_MODEL`,
`RUNBOOK_EXECUTOR_MODEL`, `PERIODIC_RUNBOOK_EXECUTOR_MODEL`, `RUNBOOK_VALIDATION_EXECUTOR_MODEL`,
`SRE_CHAT_EXECUTOR_MODEL` and `MCP_TOOL_CALLING_MODEL`. Each agent also has one more key with the
same prefix: `<prefix>_COMPACTION_MODEL` writes the summary when the history gets too long, for example
`RCA_COMPACTION_MODEL`. It returns a fixed shape, so point it at a model that supports a forced tool
call, such as Claude. The answer comes from the loop's last reply, with no model call after it. `SRE_CHAT_TITLE_MODEL` names the chat's titles and can be a cheaper model. Each
key becomes an env var of the same name.

```
helm upgrade sre-agent randoli/sre-agent -n randoli-agents \
  --set llm.provider=anthropic \
  --set models.SRE_CHAT_EXECUTOR_MODEL=claude-sonnet-4-5-20250929 \
  --set models.SRE_CHAT_TITLE_MODEL=claude-haiku-4-5-20251001
```

Every id set there must also appear in `models.yaml` for the active provider. If one does not, the
agent says so in a single startup line naming every role that is wrong, which is what you want the
first time you change provider and half the keys still hold the old ids.

### Thinking and temperature

Each agent's loop model can think before each reply, between tool calls too. The `thinkingBudgets`
map sets how many tokens it may think, one key per loop: `RCA_INVESTIGATOR_THINKING_BUDGET`,
`RUNBOOK_EXECUTOR_THINKING_BUDGET`, `PERIODIC_RUNBOOK_EXECUTOR_THINKING_BUDGET`,
`RUNBOOK_VALIDATION_EXECUTOR_THINKING_BUDGET`, `SRE_CHAT_EXECUTOR_THINKING_BUDGET` and
`MCP_TOOL_CALLING_THINKING_BUDGET`. Only Claude on `aws`, `anthropic` and `vertex` can think. Thinking
is billed as output tokens and makes each reply slower.

Thinking is off by default: `thinkingBudgets` is empty, so every agent runs with a budget of `0`. The
tested budgets are kept as commented lines under `thinkingBudgets` in `values.yaml` (6000 for RCA,
4000 for the runbook agents and the chat, 2048 for the MCP agent). To turn thinking on for an agent,
uncomment its line and change `thinkingBudgets: {}` to `thinkingBudgets:`, or set it on the command
line. A budget above `0` must be at least 1024 and below the model's `max_output_tokens` (16000 for
Sonnet 4.5); the agent names a budget that breaks this in one startup line. The agent reads these at
startup, so restart it after a change.

```
helm upgrade sre-agent randoli/sre-agent -n randoli-agents \
  --set thinkingBudgets.SRE_CHAT_EXECUTOR_THINKING_BUDGET=4000
```

`llm.temperature` is the temperature of every model call that does not think, `0.00000001` by default.
Set it to `none` to send no temperature, for a model that rejects one. A thinking model is always sent
none.

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
  --set mcpServers.loki.lokiUrl=http://my-loki:3100 \
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

- Every setting, with its `values.yaml` key and what it changes, is in [Every setting](#every-setting). The [values.yaml](charts/sre-agent/values.yaml) file holds the defaults

## Every setting

Each row is one environment variable the agent reads, the `values.yaml` key that sets it, and what it
changes. Set them with `--set <key>=<value>` or in your own values file. The defaults are what the
chart ships.

A handful of variables are not settable because the chart fixes them:
`LOG_PROVIDER` (`loki`), `TRACE_PROVIDER` (`tempo`), `OTEL_SERVICE_NAME` (`randoli-sre-agent`),
`OTEL_EXPORTER_OTLP_PROTOCOL` (`grpc`), `RUNNING_IN_KUBERNETES` (`true`),
`TOOL_RESULT_STORAGE_PATH` (`/var/lib/sre-agent/tool_results`, the mounted `emptyDir`),
`TRACELOOP_TRACE_CONTENT` (`false`), `OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT` (`1000`),
`OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT` (`100000`) and `OTEL_SPAN_EVENT_COUNT_LIMIT` (`256`).

### Credentials and the provider

These have no safe default. The agent cannot start without them.

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `LLM_PROVIDER` | `llm.provider` | `aws` | Which provider builds the models. `aws` means Bedrock |
| `AWS_REGION` | `llm.region` | `us-east-1` | Bedrock region |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | a Secret the deployment mounts | | Bedrock credentials. Other providers read their own keys instead |
| `FLIGHTSQL_URL` | `dataPlane.flightSqlUrl` | `grpc+tcp://randoli-agent:31337` | The platform datastore, which also holds the audit and chat tables |
| `AGENT_CALLBACK_URL` | `dataPlane.agentCallbackUrl` | `http://randoli-agent:8080/` | Where reports are POSTed when a request omits `callbackUrl` |
| `PROMETHEUS_URL` | `observability.prometheusUrl` | `http://randoli-obs-prometheus:80` | Metrics backend |
| `TEMPO_URL` | `observability.tempoUrl` | `http://randoli-obs-tempo:3200` | Trace backend |
| `LOG_LOKI_URL` | `observability.lokiUrl` | `http://randoli-obs-loki:3100` | Log backend |

### Budget

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `DAILY_USAGE_BUDGET_IN_USD` | `analysis.dailyBudgetUsd` | `20` | Hard daily cap on model spend. `0` turns enforcement off |
| `BUDGET_CALL_ESTIMATE_USD` | `analysis.budgetCallEstimateUsd` | `0.3` | What each call claims from the budget until it settles at its real cost |
| `BUDGET_RESERVE_WAIT_S` | `analysis.budgetReserveWaitSeconds` | `180` | How long a call waits for in-flight claims to settle when only those claims fill the budget |
| `BUDGET_RESERVE_WAIT_CHAT_S` | `analysis.budgetReserveWaitChatSeconds` | `15` | The same wait for a chat call, kept short because a user is watching. When it runs out the question is refused as busy |
| `BUDGET_REPROBE_S` | `analysis.budgetReprobeSeconds` | `60` | How long a spent-budget latch stops agents before the next call re-checks |
| `BUDGET_SWEEP_INTERVAL_S` | `analysis.budgetSweepIntervalSeconds` | `600` | How often claims left behind by crashed calls are released |

### Model calls

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `LLM_CALL_TIMEOUT_S` | `llm.callTimeoutSeconds` | `120` | Seconds one call may take before it is retried |
| `LLM_CALL_RETRIES` | `llm.callRetries` | `2` | Retries after a timed-out call. When all of them time out the run stops |
| `LLM_FIRST_TOKEN_RETRIES` | `llm.firstTokenRetries` | `1` | How often a streamed call that sent no first token in time is sent again |
| `LLM_READ_TIMEOUT_S` | `llm.readTimeoutSeconds` | `240` | Socket read timeout for the big reasoning calls |
| `LLM_SIDE_READ_TIMEOUT_S` | `llm.sideReadTimeoutSeconds` | `60` | The same for the small side calls: compaction, chat titles |
| `LLM_CONNECT_TIMEOUT_S` | `llm.connectTimeoutSeconds` | `10` | Socket connect timeout |
| `LLM_KEEP_WARM_S` | `llm.keepWarmSeconds` | `240` | One tiny call on this interval keeps the connection pool alive, because NAT gateways drop idle sockets at about 350s. `0` turns it off |
| `LLM_STREAMING` | `llm.streaming` | `true` | Stream the loop call so the first token lands early |
| `LLM_TEMPERATURE` | `llm.temperature` | `0.00000001` | Temperature of every call without thinking. Empty sends none, for a model that rejects it |
| `PROMPT_CACHE_TTL` | `llm.promptCacheTtl` | `1h` | Prompt cache lifetime. `1h` keeps it warm across a whole run |

### What an agent may investigate

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `ENABLED_NAMESPACES` | `analysis.enabledNamespaces` | `namespace1,namespace2` | Comma-separated. A request outside the list is denied. Empty means all |
| `ENABLED_WORKLOADS` | `analysis.enabledWorkloads` | empty, meaning all | The same, by workload name |
| `RCA_INVESTIGATOR_MAX_ITERATIONS` | `analysis.maxIterationsRCA` | `25` | Model calls one RCA run may make. The last one is asked for the answer with tools unbound |
| `RUNBOOK_MAX_ITERATIONS` | `analysis.maxIterationsRunbook` | `35` | The same for the runbook agent |
| `RUNBOOK_VALIDATION_MAX_ITERATIONS` | `analysis.maxIterationsRunbookValidation` | `11` | The same for runbook validation |
| `MCP_MAX_ITERATIONS` | `analysis.maxIterationsMCP` | `25` | The same for the MCP server agents, such as ticketing |
| `RCA_MIN_CONFIDENCE_FOR_FIXES` | `analysis.minConfidenceForFixesRCA` | `8` | On the 1 to 9 scale, the lowest RCA confidence that still carries fixes. Below it the report drops them |
| `AGENT_TOOL_CONCURRENCY` | `analysis.toolConcurrency` | `8` | Tool calls one step runs at once. Keep it at or below `TOOL_POOL_WORKERS` |
| `MAX_TOOL_CALLS_PER_ITERATION` | `analysis.maxToolCallsPerIteration` | `5` | Tool calls one reply may run. The model is told the limit, and calls past it are not run. `0` means no limit |
| `TOOL_TRANSIENT_RETRIES` | `analysis.toolTransientRetries` | `2` | How often an agent may re-run a call whose server timed out or was unavailable |
| `K8S_OPERATION_TIMEOUT_S` | `analysis.kubernetesOperationTimeoutSeconds` | `30` | How long an in-house Kubernetes change waits for the cluster to settle. Raising it above about 85 can outlive the tool's own call timeout |
| `CREDENTIAL_KEY_PATTERN` | `analysis.credentialKeyPattern` | a regex over password, token, secret and similar | Which field names count as credentials, so their values are blanked before anything is stored or shown |

### Tool results and the context window

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `TOOL_RESULT_MAX_WINDOW_PCT` | `analysis.toolResultMaxWindowPct` | `15` | Share of the model's window one tool result may take |
| `TOOL_RESULT_MAX_TOKENS` | `analysis.toolResultMaxTokens` | `25000` | The absolute cap on one result. The smaller of the two applies. A larger result is saved to a file and arrives as a preview the agent reads with its `bash` tool |
| `TOOL_RESULT_RETENTION_HOURS` | `analysis.toolResultRetentionHours` | `24` | How long a chat's saved results are kept. A single run's are deleted when it ends |
| `TOOL_RESULT_STORAGE_MAX_BYTES` | `analysis.toolResultStorageMaxBytes` | `1610612736` (1.5 GiB) | Byte budget for the saved results folder. Past it the sweep deletes the oldest folders no run is using. Keep it under the volume's size limit |
| `COMPACTION_TRIGGER_PCT` | `analysis.compactionTriggerPct` | `95` | Share of the window at which an agent summarizes the older part of its history |
| `COMPACTION_KEEP_RECENT_PCT` | `analysis.compactionKeepRecentPct` | `25` | Share of the window the newest replies may take and still survive a compaction unchanged |
| `BASH_TOOL_MEMORY_LIMIT_MB` | `analysis.bashToolMemoryLimitMb` | `256` | Memory each program of the read-only `bash` tool may use. One that needs more fails with a hint to read less. `0` turns the cap off |

### SRE chat

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `SRE_CHAT_MAX_ITERATIONS` | `sreChat.maxIterations` | `30` | Model calls one question may make. The last is told to answer from what it has. A reply to a clarification or an approval starts a new count |
| `SRE_CHAT_HISTORY_COUNT` | `sreChat.historyCount` | `30` | Earlier questions of the chat listed as history on every new question, as a thread id and a summary. The agent reads any of them in full with its own tool |
| `SRE_CHAT_MAX_CLARIFICATION_ROUNDS` | `sreChat.maxClarificationRounds` | `3` | Clarifying questions one question may ask. After this the agent answers with what it has |
| `SRE_CHAT_INCIDENT_HISTORY_COUNT` | `sreChat.incidentHistoryCount` | `5` | Other finished chats about the same incident loaded as background. They never appear in a payload |
| `SRE_CHAT_INCIDENT_WINDOW_BEFORE_HOURS` | `sreChat.incidentWindowBeforeHours` | `3` | How far before an incident's `occurredAt` a question about it reads. The window starts early because a problem usually begins before the detector records it |
| `SRE_CHAT_INCIDENT_WINDOW_AFTER_HOURS` | `sreChat.incidentWindowAfterHours` | `1` | How far after it, or up to now if that is sooner |
| `SRE_CHAT_TITLE_MAX_CHARS` | `sreChat.titleMaxChars` | `1000` | The chat title, and a name a user gives, is cut to this |
| `SRE_CHAT_TITLE_TIMEOUT_S` | `sreChat.titleTimeoutSeconds` | `20` | A new chat is named before the agent starts. Past this the question's own text becomes the title |
| `SRE_CHAT_MAX_RUNNING_TURNS` | `sreChat.maxRunningTurns` | `30` | Questions running at once |
| `SRE_CHAT_MAX_WAITING_TURNS` | `sreChat.maxWaitingTurns` | `64` | How many may wait behind them. Past this a question is refused as busy |
| `SRE_CHAT_WAIT_TIMEOUT_S` | `sreChat.waitTimeoutSeconds` | `30` | How long a question waits for a free place |
| `SRE_CHAT_KEEPALIVE_S` | not set, the default is used | `15` | Seconds of quiet on the answer stream before a keepalive comment is sent. It is a comment line, not a frame |

### MCP client

One pool per server and credential set. Full detail in the agent repo's `docs/mcp/mcp_session_pool.md`.

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `MCP_SESSIONS_PER_SERVER` | `mcpClient.sessionsPerServer` | `4` | Sessions one server may hold open |
| `MCP_CALLS_PER_SESSION` | `mcpClient.callsPerSession` | `16` | Calls one session carries before another is opened |
| `MCP_DEFAULT_MAX_CALLS` | `mcpClient.defaultMaxCalls` | `10` | Calls one server runs at once, for a server type with no specific limit. Set a type's own with `MCP_MAX_CALLS_<TYPE>` |
| `MCP_ACQUIRE_TIMEOUT_S` | `mcpClient.acquireTimeoutSeconds` | `4` | How long a call waits for a free slot, and again for a session |
| `MCP_CONNECT_TIMEOUT_S` | `mcpClient.connectTimeoutSeconds` | `4` | TCP connect timeout to a server |
| `MCP_OPEN_TIMEOUT_S` | `mcpClient.openTimeoutSeconds` | `15` | How long opening a session may take |
| `MCP_CALL_TIMEOUT_S` | `mcpClient.callTimeoutSeconds` | `30` | How long one call attempt may take |
| `MCP_MAX_ATTEMPTS` | `mcpClient.maxAttempts` | `2` | Attempts per call. Only a call that never reached the server, or a read-only one, is sent again |
| `MCP_RETRY_BACKOFF_S` | `mcpClient.retryBackoffSeconds` | `0.5` | Base backoff between attempts, with jitter |
| `MCP_OPEN_FAILURE_BACKOFF_S` | `mcpClient.openFailureBackoffSeconds` | `2` | How long after a failed open before another is tried, so a dead server is not reopened in a tight loop |
| `MCP_SESSION_MAX_AGE_S` | `mcpClient.sessionMaxAgeSeconds` | `600` | Age at which a session is retired once its calls finish |
| `MCP_SESSION_IDLE_S` | `mcpClient.sessionIdleSeconds` | `300` | Idle time at which it is closed |

### Server and pools

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `SERVER_BACKLOG` | `server.backlog` | `4096` | Pending connections the server accepts |
| `SERVER_LIMIT_CONCURRENCY` | `server.limitConcurrency` | `0`, meaning no limit | Requests the server handles at once |
| `SERVER_TIMEOUT_KEEP_ALIVE_S` | `server.timeoutKeepAliveSeconds` | `5` | How long an idle connection is held |
| `SERVER_TIMEOUT_GRACEFUL_SHUTDOWN_S` | `server.timeoutGracefulShutdownSeconds` | `30` | How long shutdown waits for work in flight |
| `OUTBOUND_HTTP_TIMEOUT_S` | `server.outboundHttpTimeoutSeconds` | `30` | Timeout on the agent's own outbound HTTP, such as posting a report |
| `LLM_POOL_WORKERS` | `server.workers.llm` | `64` | Threads for model calls. It also sizes the event loop's default executor, which streamed calls run on |
| `TOOL_POOL_WORKERS` | `server.workers.tool` | `64` | Threads available to run tool calls. The ceiling `AGENT_TOOL_CONCURRENCY` must not exceed |
| `DB_POOL_WORKERS` | `server.workers.db` | `4` | Threads for database calls. Keep it equal to `dataPlane.dbPoolMaxConnections` |
| `BLOCKING_POOL_WORKERS` | `server.workers.blocking` | `8` | Threads for other blocking work, such as writing saved results and reading cluster RBAC |
| `RATE_LIMIT_ENABLED` | `server.rateLimit.enabled` | `true` | Per-endpoint and per-client limits. Over a limit answers 429 with `Retry-After` |
| `RATE_LIMIT_ENDPOINT_BURST` | `server.rateLimit.endpointBurst` | `2000` | Requests one endpoint takes at once, from all clients together |
| `RATE_LIMIT_ENDPOINT_PER_SECOND` | `server.rateLimit.endpointPerSecond` | `200` | And per second after that |
| `RATE_LIMIT_CLIENT_BURST` | `server.rateLimit.clientBurst` | `1000` | The same for one client on one endpoint |
| `RATE_LIMIT_CLIENT_PER_SECOND` | `server.rateLimit.clientPerSecond` | `100` | And per second after that |
| `RATE_LIMIT_MAX_CLIENTS` | `server.rateLimit.maxClients` | `10000` | Clients remembered at once. The one idle longest is forgotten first. A client is the first `X-Forwarded-For` address, else the peer address |

### Datastore

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `DB_POOL_MAX_CONNECTIONS` | `dataPlane.dbPoolMaxConnections` | `4` | Database connections open at once across the process, and so statements running at once |
| `DB_POOL_ACQUIRE_TIMEOUT_S` | `dataPlane.dbPoolAcquireTimeoutSeconds` | `30` | How long a statement waits for a free connection before failing |
| `DB_POOL_IDLE_TIMEOUT_S` | `dataPlane.dbPoolIdleTimeoutSeconds` | `60` | Idle time after which a connection is closed |
| `DB_POOL_MAX_IDLE` | `dataPlane.dbPoolMaxIdle` | `1` | Connections kept open between uses; the rest are closed as soon as they are handed back |
| `DB_POOL_REAP_INTERVAL_S` | `dataPlane.dbPoolReapIntervalSeconds` | `15` | How often a background thread closes idle connections past the idle timeout |
| `DB_TIMEOUT_QUERY_S`, `DB_TIMEOUT_FETCH_S`, `DB_TIMEOUT_UPDATE_S` | `dataPlane.dbTimeoutSeconds` | `10` | Timeouts on a statement, on fetching its rows, and on a write. One value sets all three |
| `DB_MAX_MSG_SIZE_S` | `dataPlane.dbMaxMessageSizeBytes` | `67108864` (64 MiB) | Largest FlightSQL message accepted |
| `HEALTH_DB_CHECK_TTL_S` | `dataPlane.healthDbCheckTtlSeconds` | `5` | How long `/health` reuses its last database check instead of making a new one |

### Observability

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `OTEL_DISABLED` | `observability.otelDisabled` | `false` | Turns the agent's own tracing and metrics export off |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `observability.otelExporterEndpoint` | `http://randoli-otel-collector:4317` | Where spans and metrics go |
| `TRACELOOP_BASE_URL` | `observability.traceLoopBaseUrl` | `http://randoli-otel-collector:4318` | Where the LLM instrumentation sends its spans. Read by the Traceloop SDK, not by the agent |
| `LOG_LEVEL` | `logLevel` | `INFO` | Log level for the agent's own logs |
| `LOG_LOKI_TIMEOUT` | `observability.lokiTimeoutSeconds` | `100` | Timeout on a log query |
| `TEMPO_TIMEOUT` | `observability.tempoTimeoutSeconds` | `30` | Timeout on a trace query |

### Models and thinking

One key per role under `models:`, and one per loop role under `thinkingBudgets:`. Both are covered in
[Choosing the models](#choosing-the-models).

| Variable | Chart value | Default | What it does |
|---|---|---|---|
| `RCA_INVESTIGATOR_MODEL`, `RUNBOOK_EXECUTOR_MODEL`, `PERIODIC_RUNBOOK_EXECUTOR_MODEL`, `RUNBOOK_VALIDATION_EXECUTOR_MODEL`, `SRE_CHAT_EXECUTOR_MODEL`, `MCP_TOOL_CALLING_MODEL` | `models.<KEY>` | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | The model each agent's loop runs on |
| `<prefix>_COMPACTION_MODEL` for `RCA`, `RUNBOOK`, `PERIODIC_RUNBOOK`, `RUNBOOK_VALIDATION`, `SRE_CHAT`, `MCP` | `models.<KEY>` | the same | The model that summarizes an agent's older history |
| `SRE_CHAT_TITLE_MODEL` | `models.SRE_CHAT_TITLE_MODEL` | the same | The model that names a new chat |
| `<role>_THINKING_BUDGET` | `thinkingBudgets.<KEY>` | unset, meaning `0` | Tokens that role's model may think before each reply. A value above `0` must be at least `1024` |

## Troubleshooting
- If you see this log message: "The security token included in the request is invalid", check that the credentials are properly set and that they are exposed to the randoli-sre-agent pod as the following environment variables: AWS_ACCESS_KEY_ID, AWS_REGION and AWS_SECRET_ACCESS_KEY
