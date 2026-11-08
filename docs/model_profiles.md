# <u>Model profiles in the sre-agent chart</u>

## <u>Contents</u>

- [1 What you configure](#1-what-you-configure)
- [2 Credentials](#2-credentials)
- [3 Models per profile](#3-models-per-profile)
  - [3.1 aws](#31-aws)
  - [3.2 anthropic](#32-anthropic)
  - [3.3 More profiles later](#33-more-profiles-later)
- [4 The mapping behind each profile](#4-the-mapping-behind-each-profile)
  - [4.1 Where the mapping lives](#41-where-the-mapping-lives)
  - [4.2 aws](#42-aws)
  - [4.3 anthropic](#43-anthropic)
  - [4.4 What each field means](#44-what-each-field-means)
- [5 Examples](#5-examples)
- [6 After a change](#6-after-a-change)
- [7 Keeping this doc current](#7-keeping-this-doc-current)

<br>

## <u>1 What you configure</u>

Three chart values pick the agent's model profile. They are the only model settings in the chart.

| Chart key | Env var in the pod | Values today | Default |
|---|---|---|---|
| `llm.provider` | `LLM_PROVIDER` | `aws` (Amazon Bedrock), `anthropic` (the Anthropic API) | `aws` |
| `llm.family` | `MODEL_FAMILY` | `claude` | `claude` |
| `llm.preset` | `MODEL_PRESET` | `balanced` | `balanced` |

- Each combination maps to one profile. The profile holds every flag the agent needs for its models.
- You never set those flags. They are our mapping (section 4).
- Each value is an enum in [values.schema.json](../charts/sre-agent/values.schema.json), so Helm
  refuses a value with no profile:

```text
Error: values don't meet the specifications of the schema(s) in the following chart(s):
sre-agent:
- llm.family: llm.family must be one of the following: "claude"
```

<br>

## <u>2 Credentials</u>

The chart checks `llm.provider` first and gives the agent only that provider's settings. Keys are read
by name from the Secret named by `llm.credentialsSecretName` (default `randoli-sre-agent-secret`).
The chart does not create the Secret.

| `llm.provider` | Keys read from the Secret | Other chart values it gets |
|---|---|---|
| `aws` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `llm.region`, sent as `AWS_REGION` (default `us-east-1`) |
| `anthropic` | `ANTHROPIC_API_KEY` | none |

- Any other key in the Secret is not loaded.
- A missing key stops the pod at rollout with `CreateContainerConfigError`, naming the Secret and key.
- The agent works the same way: it reads `LLM_PROVIDER` first, then only that provider's variables.
- For `aws`, the IAM user needs `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream`
  on both models and their inference profiles.

<br>

## <u>3 Models per profile</u>

Each profile puts a high reasoning model on the agent loops (investigations, runbooks, chat and the
report each one fills in) and a low reasoning model on compaction summaries and chat titles.

### <u>3.1 aws</u>

| `llm.provider` | `llm.family` | `llm.preset` | High reasoning model | Low reasoning model |
|---|---|---|---|---|
| `aws` | `claude` | `balanced` | `us.anthropic.claude-sonnet-5-5` | `us.anthropic.claude-haiku-5-5` |

<br>

### <u>3.2 anthropic</u>

| `llm.provider` | `llm.family` | `llm.preset` | High reasoning model | Low reasoning model |
|---|---|---|---|---|
| `anthropic` | `claude` | `balanced` | `claude-sonnet-5-5` | `claude-haiku-5-5` |

<br>

### <u>3.3 More profiles later</u>

- Planned, not available yet: the families nova, mistral, deepseek, qwen and gpt-oss on `aws`, and
  the `quality` preset (the strongest model on every job).
- Each one is added only after its models pass every check on every route, as listed in
  [model_profile_setup.md §6](../../insights-recommendation-service/insights-recommendation-service/docs/model-profiles/model_profile_setup.md#6-before-a-model-is-supported).
- Then it gets a row in section 3, columns in section 4, and its name in the chart's enum.
- The chart's `values.yaml` comments and `TODO.md` track the list.

<br>

## <u>4 The mapping behind each profile</u>

### <u>4.1 Where the mapping lives</u>

| Repo | Path | What it is |
|---|---|---|
| insights-recommendation-service | `modelprofiles/profiles.json` | the mapping: every profile and every model's flags |
| insights-recommendation-service | `internal/modelprofile/` | loads and checks it, and serves it at `GET /recommendations/api/v1/model-profiles` |
| ai-agent | `recommendation_service/spec.py` | fetches the profile at startup, with the prompts and schemas |
| helm-charts-small | `charts/sre-agent/values.schema.json` | the enums of the three chart values |

The agent fetches its profile once at startup, from `recommendationService.url`, before anything else.
It serves nothing until the fetch succeeds, and retries with backoff while the service cannot be
reached.

<br>

### <u>4.2 aws</u>

| Field | High reasoning | Low reasoning |
|---|---|---|
| `llm.provider` / `llm.family` / `llm.preset` | `aws` / `claude` / `balanced` | `aws` / `claude` / `balanced` |
| Runs | the agent loops | compaction summaries, chat titles |
| `id` | `us.anthropic.claude-sonnet-5-5` | `us.anthropic.claude-haiku-5-5` |
| `schema_output` | `true` | `true` |
| `schema_with_tools` | `true` | `false` |
| `tool_choice` | `false` | `true` |
| `thinking.type` | `between_tools` | `disabled` |
| `thinking.effort` | empty, so `default_effort` | empty, so `default_effort` |
| `thinking.budget_tokens` | `0` | `0` |
| `thinking_modes` | `between_tools`: off, effort `low` to `high`; `adaptive`: thinks, effort `low` to `max` | `disabled`: off, effort `low` to `high`; `adaptive`: thinks, effort `low` to `max` |
| `default_effort` | `high` | `medium` |
| `temperature` | null | null |
| `context_window` | `1000000` | `1000000` |
| `max_output` | `32000` | `32000` |
| `prices` | [model_prices.md §4](../../insights-recommendation-service/insights-recommendation-service/docs/model-profiles/model_prices.md#4-the-prices-today) | [model_prices.md §4](../../insights-recommendation-service/insights-recommendation-service/docs/model-profiles/model_prices.md#4-the-prices-today) |

<br>

### <u>4.3 anthropic</u>

| Field | High reasoning | Low reasoning |
|---|---|---|
| `llm.provider` / `llm.family` / `llm.preset` | `anthropic` / `claude` / `balanced` | `anthropic` / `claude` / `balanced` |
| Runs | the agent loops | compaction summaries, chat titles |
| `id` | `claude-sonnet-5-5` | `claude-haiku-5-5` |
| `schema_output` | `true` | `true` |
| `schema_with_tools` | `true` | `false` |
| `tool_choice` | `false` | `true` |
| `thinking.type` | `between_tools` | `disabled` |
| `thinking.effort` | empty, so `default_effort` | empty, so `default_effort` |
| `thinking.budget_tokens` | `0` | `0` |
| `thinking_modes` | `between_tools`: off, effort `low` to `high`; `adaptive`: thinks, effort `low` to `max` | `disabled`: off, effort `low` to `high`; `adaptive`: thinks, effort `low` to `max` |
| `default_effort` | `high` | `medium` |
| `temperature` | null | null |
| `context_window` | `1000000` | `1000000` |
| `max_output` | `32000` | `32000` |
| `prices` | [model_prices.md §4](../../insights-recommendation-service/insights-recommendation-service/docs/model-profiles/model_prices.md#4-the-prices-today) | [model_prices.md §4](../../insights-recommendation-service/insights-recommendation-service/docs/model-profiles/model_prices.md#4-the-prices-today) |

<br>

### <u>4.4 What each field means</u>

| Field | Meaning |
|---|---|
| `id` | the model id exactly as the provider takes it |
| `schema_output` | the provider holds a structured reply to its JSON schema |
| `schema_with_tools` | the provider can hold a reply's text to a schema while tools are bound. The agent does not use it: loop calls hold no schema, because a held schema next to the tools made the model's comment before its calls become the whole reply |
| `tool_choice` | the agent may force a tool call |
| `thinking.type` | the thinking setting every call carries; one of the model's `thinking_modes` |
| `thinking.effort`, `thinking.budget_tokens` | the effort and budget sent; empty effort means the model's `default_effort` |
| `thinking_modes` | every thinking type the model takes, whether it thinks in it, and the efforts it takes |
| `default_effort` | the effort the model uses when none is sent |
| `temperature` | sent only when set; neither model takes one |
| `context_window` | tokens one call can hold |
| `max_output` | the longest reply the agent asks for |
| `prices` | USD per token, for the daily budget; Haiku 5.5 costs more above 100,000 prompt tokens |

The full reference, the startup checks and the checks a model must pass are in
[model_profile_setup.md](../../insights-recommendation-service/insights-recommendation-service/docs/model-profiles/model_profile_setup.md).

<br>

## <u>5 Examples</u>

The default, written out:

```
helm upgrade sre-agent randoli/sre-agent -n randoli-agents \
  --set llm.provider=aws --set llm.family=claude --set llm.preset=balanced --set llm.region=us-east-1
```

The Anthropic API, with its key in the credentials Secret:

```
kubectl -n randoli-agents create secret generic randoli-sre-agent-secret \
  --from-literal=ANTHROPIC_API_KEY=<your-api-key>
helm upgrade sre-agent randoli/sre-agent -n randoli-agents --set llm.provider=anthropic
```

A values file:

```yaml
llm:
  provider: aws
  family: claude
  preset: balanced
  region: us-east-1
  credentialsSecretName: randoli-sre-agent-secret
```

<br>

## <u>6 After a change</u>

- A `helm upgrade` that changes `llm.provider`, `llm.family`, `llm.preset` or `llm.region` rolls the
  pod.
- A change to the credentials Secret alone does not. Restart the agent after it.

To switch provider:

1. Put the new provider's keys in the credentials Secret (section 2).
2. Set `llm.provider` with `helm upgrade`.
3. Check the startup log: each model's `[<provider>.llm.ok]` line names its id, thinking type,
   effort and temperature.

<br>

## <u>7 Keeping this doc current</u>

| Change | Update |
|---|---|
| a new profile | a row in its provider's table in section 3, and two columns in its provider's table in section 4 |
| a new provider | a subsection in section 3, one in section 4, and a row in section 2 |
| a changed flag | its cell in section 4 |
| a new field | a row in every table in section 4, and in section 4.4 |
| a price | nothing here: prices live only in [model_prices.md](../../insights-recommendation-service/insights-recommendation-service/docs/model-profiles/model_prices.md) |

The same tables are in the ai-agent and recommendation service docs. Change all three together.
