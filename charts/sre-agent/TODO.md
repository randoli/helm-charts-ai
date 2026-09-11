Conditionally Installed (Based on umbrella values)
- OpenCost MCP -> aiAgent.enabled && cost.enabled
- Tempo MCP -> DONE (templates/mcp/mcp-tempo) — CR-only, points at <observability.tempoUrl>/api/mcp
- Loki MCP -> DONE (templates/mcp/mcp-loki) — Deployment+Service+CR via randoli/loki-mcp image
- Promethus MCP -> DONE (templates/mcp/mcp-prometheus) — Deployment+Service+CR via ghcr.io/tjhop/prometheus-mcp-server, queries observability.prometheusUrl
- Kubernetes/Openshift MCP -> DONE on Kubernetes (templates/mcp/mcp-kubernetes, auto-disabled on OpenShift via global.openshift.enabled)

TODO
- Agent MCP -> 
- RandoliPlatformMCP -> 

Customer Managed (Will be added to docs)
- GitHub (Auth via github app)
- ArgoCD
- Atlassian (research)
- Strimzi (Image needs to be built and published)
- Kyverno (Image needs to be built and published)
