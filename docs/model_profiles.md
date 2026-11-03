# <u>Model profiles in the sre-agent chart</u>

## <u>Contents</u>

- [1 The values](#1-the-values)
- [2 Combinations per provider](#2-combinations-per-provider)
  - [2.1 aws](#21-aws)
    - [2.1.1 claude](#211-claude)
    - [2.1.2 nova](#212-nova)
    - [2.1.3 mistral](#213-mistral)
    - [2.1.4 deepseek](#214-deepseek)
    - [2.1.5 qwen](#215-qwen)
    - [2.1.6 gpt-oss](#216-gpt-oss)
  - [2.2 anthropic](#22-anthropic)
    - [2.2.1 claude](#221-claude)
  - [2.3 vertex](#23-vertex)
    - [2.3.1 claude](#231-claude)
    - [2.3.2 gemini](#232-gemini)
  - [2.4 openai](#24-openai)
    - [2.4.1 gpt](#241-gpt)
  - [2.5 azure_openai](#25-azure_openai)
    - [2.5.1 gpt](#251-gpt)
  - [2.6 azure_deepseek](#26-azure_deepseek)
    - [2.6.1 deepseek](#261-deepseek)
- [3 Credentials: where each key goes](#3-credentials-where-each-key-goes)
- [4 Examples](#4-examples)
- [5 Pricing file](#5-pricing-file)
- [6 Families not offered](#6-families-not-offered)
- [7 After a change](#7-after-a-change)

<br>

## <u>1 The values</u>

| Chart key | Env var in the pod | Values | Empty means |
|---|---|---|---|
| `llm.provider` | `LLM_PROVIDER` | `aws`, `anthropic`, `vertex`, `openai`, `azure_openai`, `azure_deepseek`; also `azure_anthropic`, `azure_meta`, `azure_mistral`, which have no families | (default `aws`) |
| `llm.family` | `MODEL_FAMILY` | `claude`, `gemini`, `gpt`, `nova`, `mistral`, `deepseek`, `qwen`, `gpt-oss`, as the provider offers them | the provider's default family |
| `llm.preset` | `MODEL_PRESET` | `balanced`: a strong model on the agent loops and the family's lighter model on compaction and chat titles. `quality`: the family's strongest model on every role, Sonnet 5.5 for `claude` | `balanced` |

The defaults give the agent loops `us.anthropic.claude-sonnet-5-5` and compaction and
chat titles `us.anthropic.claude-haiku-4-5-20251001-v1:0`. Before profiles, the chart put Sonnet 4.5
on every role; no combination does that now. A value outside its list stops the agent at start with a log line that names the
setting and lists its valid values.

<br>

## <u>2 Combinations per provider</u>

One sub-section per provider and one per family. Each row is a combination: set those values in
the chart and the roles get those models. We choose the model versions; a deployment picks only the
provider, family and preset. The other ids listed under a family can replace its defaults in the
agent's map, once the id is in `templates/models-configmap.yaml`.

Our evals have run with Sonnet 4.5 on every role on `aws`, and Sonnet 5.5 on every role on `anthropic`
for RCA cases. The `aws` default, Sonnet 5.5 with Haiku 4.5, has not been run as a whole. Run them before
relying on a combination. The AWS identity the agent uses must be allowed both models.

"Agent loops" means every agent loop role: `RCA_INVESTIGATOR_MODEL`, `RUNBOOK_EXECUTOR_MODEL`,
`PERIODIC_RUNBOOK_EXECUTOR_MODEL`, `RUNBOOK_VALIDATION_EXECUTOR_MODEL`, `SRE_CHAT_EXECUTOR_MODEL` and
`MCP_TOOL_CALLING_MODEL`. "Compaction and chat title" means every `*_COMPACTION_MODEL` and
`SRE_CHAT_TITLE_MODEL`.

<br>

### <u>2.1 aws</u>

Amazon Bedrock.
#### <u>2.1.1 claude</u>

Set these keys, and the roles get these models. The default family on this provider. Leaving the preset out gives `balanced`.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: aws`<br>`llm.family: claude`<br>`llm.preset: quality` | `us.anthropic.claude-sonnet-5-5` | `us.anthropic.claude-sonnet-5-5` |
| `llm.provider: aws`<br>`llm.family: claude`<br>`llm.preset: balanced` (default) | `us.anthropic.claude-sonnet-5-5` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |

Other ids that can replace these defaults:

- For the agent loops:
  - `global.anthropic.claude-sonnet-5-5`: 10% cheaper than `us.`, routed worldwide
  - `us.anthropic.claude-sonnet-4-5-20250929-v1:0`: older and dearer per token, can think, legacy with an end of life of 2027-04-08
- For compaction and chat titles:
  - `us.anthropic.claude-haiku-5-5`: newer generation, already priced
  - `global.anthropic.claude-haiku-5-5`: 10% cheaper than `us.`, routed worldwide

#### <u>2.1.2 nova</u>

Set these keys, and the roles get these models. This family has one model on aws that fits both roles, so both presets give the same models and the preset can be left out.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: aws`<br>`llm.family: nova`<br>`llm.preset: quality or balanced` | `us.amazon.nova-2-lite-v1:0` | `us.amazon.nova-2-lite-v1:0` |

Other ids that can replace these defaults:

- For the agent loops:
  - `global.amazon.nova-2-lite-v1:0`: about 10% cheaper than `us.`
- For compaction and chat titles:
  - `us.amazon.nova-lite-v1:0`: 300K window, too small to compact a Nova 2 Lite run

#### <u>2.1.3 mistral</u>

Set these keys, and the roles get these models. This family has one model on aws that fits both roles, so both presets give the same models and the preset can be left out.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: aws`<br>`llm.family: mistral`<br>`llm.preset: quality or balanced` | `mistral.mistral-large-3-675b-instruct` | `mistral.mistral-large-3-675b-instruct` |

Other ids that can replace these defaults:

- For compaction and chat titles:
  - `mistral.ministral-3-14b-instruct`: cheaper, 128K window

#### <u>2.1.4 deepseek</u>

Set these keys, and the roles get these models. This family has one model on aws that fits both roles, so both presets give the same models and the preset can be left out.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: aws`<br>`llm.family: deepseek`<br>`llm.preset: quality or balanced` | `deepseek.v3.2` | `deepseek.v3.2` |

Other ids that can replace these defaults:

- For the agent loops:
  - `deepseek.v3-v1:0`: DeepSeek V3.1, legacy

#### <u>2.1.5 qwen</u>

Set these keys, and the roles get these models. This family has one model on aws that fits both roles, so both presets give the same models and the preset can be left out.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: aws`<br>`llm.family: qwen`<br>`llm.preset: quality or balanced` | `qwen.qwen3-235b-a22b-2507-v1:0` | `qwen.qwen3-235b-a22b-2507-v1:0` |

Other ids that can replace these defaults:

- For compaction and chat titles:
  - `qwen.qwen3-next-80b-a3b`: cheaper; runtime price not confirmed
  - `qwen.qwen3-coder-30b-a3b-v1:0`: already priced; no forced tool calls

#### <u>2.1.6 gpt-oss</u>

Set these keys, and the roles get these models. Leaving the preset out gives `balanced`.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: aws`<br>`llm.family: gpt-oss`<br>`llm.preset: quality` | `openai.gpt-oss-120b-1:0` | `openai.gpt-oss-120b-1:0` |
| `llm.provider: aws`<br>`llm.family: gpt-oss`<br>`llm.preset: balanced` (default) | `openai.gpt-oss-120b-1:0` | `openai.gpt-oss-20b-1:0` |

<br>

### <u>2.2 anthropic</u>

The Anthropic API.
#### <u>2.2.1 claude</u>

Set these keys, and the roles get these models. The default family on this provider. Leaving the preset out gives `balanced`.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: anthropic`<br>`llm.family: claude`<br>`llm.preset: quality` | `claude-sonnet-5-5` | `claude-sonnet-5-5` |
| `llm.provider: anthropic`<br>`llm.family: claude`<br>`llm.preset: balanced` (default) | `claude-sonnet-4-5-20250929` | `claude-haiku-4-5-20251001` |

Other ids that can replace these defaults:

- For the agent loops:
  - `claude-sonnet-4-5`: alias of the dated id
- For compaction and chat titles:
  - `claude-haiku-5-5`: newer generation, already priced
  - `claude-haiku-4-5`: alias of the dated id

<br>

### <u>2.3 vertex</u>

Google Vertex AI.
#### <u>2.3.1 claude</u>

Set these keys, and the roles get these models. The default family on this provider. Leaving the preset out gives `balanced`.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: vertex`<br>`llm.family: claude`<br>`llm.preset: quality` | `claude-sonnet-5-5` | `claude-sonnet-5-5` |
| `llm.provider: vertex`<br>`llm.family: claude`<br>`llm.preset: balanced` (default) | `claude-sonnet-4-5@20250929` | `claude-haiku-4-5@20251001` |

Other ids that can replace these defaults:

- For the agent loops:
  - `claude-sonnet-4-5`: the id without `@date`; not tested
- For compaction and chat titles:
  - `claude-haiku-5-5`: newer generation, already priced

#### <u>2.3.2 gemini</u>

Set these keys, and the roles get these models. Leaving the preset out gives `balanced`.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: vertex`<br>`llm.family: gemini`<br>`llm.preset: quality` | `gemini-4-argon` | `gemini-4-argon` |
| `llm.provider: vertex`<br>`llm.family: gemini`<br>`llm.preset: balanced` (default) | `gemini-4-argon` | `gemini-3.5-flash-lite` |

Other ids that can replace these defaults:

- For the agent loops:
  - `gemini-3.8-flash`: GA, cheaper reasoning model
  - `gemini-3.1-pro-preview`: preview only
- For compaction and chat titles:
  - `gemini-3.1-flash-lite`: GA, already priced

<br>

### <u>2.4 openai</u>

The OpenAI API, or any server that speaks it.
#### <u>2.4.1 gpt</u>

Set these keys, and the roles get these models. The default family on this provider. Leaving the preset out gives `balanced`.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: openai`<br>`llm.family: gpt`<br>`llm.preset: quality` | `gpt-5.4` | `gpt-5.4` |
| `llm.provider: openai`<br>`llm.family: gpt`<br>`llm.preset: balanced` (default) | `gpt-5.4` | `gpt-5.4-mini` |

Other ids that can replace these defaults:

- For the agent loops:
  - `gpt-5.5`: Chat Completions with tools; not priced yet
  - `gpt-6.1-sol`: tools need the Responses API, which the openai provider does not use
- For compaction and chat titles:
  - `gpt-6-luna`: tools only with reasoning_effort none on Chat Completions

<br>

### <u>2.5 azure_openai</u>

Azure OpenAI. Model ids are deployment names.
#### <u>2.5.1 gpt</u>

Set these keys, and the roles get these models. The default family on this provider. Leaving the preset out gives `balanced`.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: azure_openai`<br>`llm.family: gpt`<br>`llm.preset: quality` | `gpt-5.4` | `gpt-5.4` |
| `llm.provider: azure_openai`<br>`llm.family: gpt`<br>`llm.preset: balanced` (default) | `gpt-5.4` | `gpt-5.4-mini` |

Other ids that can replace these defaults:

- For the agent loops:
  - `gpt-5.5`: deployment name; not priced yet
  - `gpt-6.1-sol`: tools on the Responses API only

<br>

### <u>2.6 azure_deepseek</u>

DeepSeek on Azure AI Foundry.
#### <u>2.6.1 deepseek</u>

Set these keys, and the roles get these models. The default family on this provider. Leaving the preset out gives `balanced`.

| Keys | Agent loops get | Compaction and chat title get |
|---|---|---|
| `llm.provider: azure_deepseek`<br>`llm.family: deepseek`<br>`llm.preset: quality` | `DeepSeek-V4-Pro` | `DeepSeek-V4-Pro` |
| `llm.provider: azure_deepseek`<br>`llm.family: deepseek`<br>`llm.preset: balanced` (default) | `DeepSeek-V4-Pro` | `DeepSeek-V4-Flash` |

Other ids that can replace these defaults:

- For the agent loops:
  - `DeepSeek-V3.2`: older, 128K window

<br>

## <u>3 Credentials: where each key goes</u>

The chart loads the whole Secret named by `llm.credentialsSecretName` (default
`randoli-sre-agent-secret`) into the pod's environment. The chart does not create it. Put the keys
your provider reads in it:

| `llm.provider` | Keys in the `llm.credentialsSecretName` Secret | Other chart values |
|---|---|---|
| `aws` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`; `AWS_REGION` optional | `llm.region` sets `AWS_REGION` (default `us-east-1`) |
| `anthropic` | `ANTHROPIC_API_KEY` | |
| `vertex` | `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION` | `llm.googleCredentialsSecretName`: a second Secret holding the service account key file under the key `key.json`. The chart mounts it at `/var/secrets/google/key.json` and sets `GOOGLE_APPLICATION_CREDENTIALS` to that path |
| `openai` | `OPENAI_API_KEY`; `OPENAI_BASE_URL` for any endpoint that is not api.openai.com | |
| `azure_openai` | `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY`, `OPENAI_API_VERSION` | |
| `azure_deepseek` | `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY`, `OPENAI_API_VERSION` | |

What each provider needs on its side:

- **aws:** the IAM user needs `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` on the
  family's models and inference profiles, and the models must be enabled in the account. The `us.`
  ids are cross-region inference profiles. `mistral`, `deepseek`, `qwen` and `gpt-oss` have none and
  are called in `llm.region`; Qwen3 235B is not in `us-east-1`.
- **vertex:** enable the Claude models in Model Garden. For the Claude 5.5 models use the `global`
  location, or `us` or `eu`.
- **azure_openai:** model ids are deployment names. Deploy `gpt-5.4` and `gpt-5.4-mini` under those
  names.

<br>

## <u>4 Examples</u>

The default, written out:

```
helm upgrade sre-agent randoli/sre-agent -n randoli-agents \
  --set llm.provider=aws --set llm.family=claude --set llm.preset=balanced
```

Sonnet 5.5 on every role:

```
helm upgrade sre-agent randoli/sre-agent -n randoli-agents --set llm.preset=quality
```

Claude on the Anthropic API, with its key in the credentials Secret:

```
kubectl -n randoli-agents create secret generic randoli-sre-agent-secret \
  --from-literal=ANTHROPIC_API_KEY=<your-api-key>
helm upgrade sre-agent randoli/sre-agent -n randoli-agents \
  --set llm.provider=anthropic --set llm.family=claude
```

Gemini on Vertex, with the key file in its own Secret:

```
kubectl -n randoli-agents create secret generic randoli-sre-agent-secret \
  --from-literal=GOOGLE_CLOUD_PROJECT=<project-id> --from-literal=GOOGLE_CLOUD_LOCATION=global
kubectl -n randoli-agents create secret generic randoli-sre-agent-google \
  --from-file=key.json=<path-to-service-account-key.json>
helm upgrade sre-agent randoli/sre-agent -n randoli-agents \
  --set llm.provider=vertex --set llm.family=gemini \
  --set llm.googleCredentialsSecretName=randoli-sre-agent-google
```

A values file:

```yaml
llm:
  provider: aws
  family: claude
  preset: balanced
  credentialsSecretName: randoli-sre-agent-secret
```

<br>

## <u>5 Pricing file</u>

`charts/sre-agent/templates/models-configmap.yaml` prices every model in every family, for every
provider, and the agent only builds the active provider's entries. Its per-model flags matter here:
the Claude Sonnet 5.5 entries (one of the other ids) and the models with undocumented forced tool calls carry
`supports_tool_choice: false`, so the agent asks for a schema instead of forcing it, and Nova and
Gemini carry `supports_prompt_cache: false`.

<br>

## <u>6 Families not offered</u>

| Provider | Why not |
|---|---|
| `azure_meta` | no Llama model on Azure AI Foundry supports tool calling |
| `azure_mistral` | Mistral Large 3 is in preview only on Foundry; the smaller models lack tool calling or a long enough window |
| `azure_anthropic` | Claude on Foundry uses the Anthropic Messages API, not the route this provider calls |

The chart cannot set these providers' models: they need every role set in the agent's environment.

<br>

## <u>7 After a change</u>

The agent reads these values at start, so a `helm upgrade` that changes them rolls the pod. The full
mapping, with how a role gets its model, is in the ai-agent repo at
`docs/model-provider/model_profiles.md`.
