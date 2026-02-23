# Langflow Agent Template

An agentic template for building, testing, and deploying Langflow-based AI agents on OpenShift.

## Architecture

```
LOCAL (podman-compose)              CLUSTER (Helm + OpenShift)
┌─────────────────────┐             ┌─────────────────────────┐
│  Langflow UI :7860  │             │  Langflow (Deployment)  │
│         │           │             │         │               │
│         ▼           │             │         ▼               │
│  Ollama :11434      │             │  vLLM + KServe          │
│  (local LLM)        │  export     │  (GPU model serving)    │
│         │           │ ────────►   │         │               │
│         ▼           │  flow       │         ▼               │
│  PostgreSQL :5432   │             │  PostgreSQL (Bitnami)   │
│         │           │             │         │               │
│         ▼           │             │         ▼               │
│  MLflow :5000       │             │  MLflow (Deployment)    │
│  Langfuse :3000     │             │                         │
└─────────────────────┘             └─────────────────────────┘
```

Both environments expose the same OpenAI-compatible API to Langflow, so flows built locally work on the cluster without changes.

## Quick Start

### Prerequisites

- **Local**: Podman + podman-compose
- **Cluster**: `oc` CLI + `helm` CLI + access to an OpenShift cluster

### Local Development

```bash
# Start all services (Langflow, PostgreSQL, Ollama, Langfuse, MLflow)
./scripts/deploy-local.sh

# Open Langflow UI
open http://localhost:7860

# View traces in Langfuse
open http://localhost:3000

# View experiments in MLflow
open http://localhost:5000
```

### Deploy to OpenShift

```bash
# Login to your cluster
oc login https://your-cluster:6443

# Deploy the full stack
./scripts/deploy-cluster.sh

# Validate
helm test langflow-agent -n langflow-agent
```

### Export a Flow to the Cluster

```bash
# Export a flow built in the local Langflow UI
./scripts/export-flow.sh flows/example-rag-flow.json quay.io/your-org v1.0

# This builds a container image with the flow baked in, pushes it,
# then you deploy it via:
helm upgrade langflow-agent ./helm/langflow-agent \
  --set langflow.image=quay.io/your-org/langflow-example-rag-flow:v1.0
```

## Project Structure

```
langflow-agent-template/
├── local/                         # Local dev environment
│   ├── podman-compose.yml         # Langflow + PostgreSQL + Ollama + Langfuse + MLflow
│   └── .env.example               # Environment variables
│
├── helm/langflow-agent/           # Cluster deployment (Helm)
│   ├── Chart.yaml                 # Umbrella chart + Bitnami PostgreSQL dependency
│   ├── values.yaml                # All configurable values
│   └── charts/
│       ├── langflow/              # Langflow server + UI
│       ├── model-serving/         # vLLM + KServe InferenceService
│       └── mlflow/                # MLflow tracking server
│
├── flows/                         # Langflow flow definitions
│   └── example-rag-flow.json
│
└── scripts/
    ├── deploy-local.sh            # Start local env
    ├── deploy-cluster.sh          # Deploy to OpenShift
    └── export-flow.sh             # Export flow → container image → registry
```

## Configuration

### Disabling Components

Deploy without model serving (use an external LLM endpoint):
```bash
helm upgrade --install langflow-agent ./helm/langflow-agent \
  --set modelServing.enabled=false \
  --set langflow.modelEndpoint=https://your-external-llm/v1
```

Deploy without MLflow:
```bash
helm upgrade --install langflow-agent ./helm/langflow-agent \
  --set mlflow.enabled=false
```

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `langflow.image` | Langflow container image | `langflowai/langflow:latest` |
| `langflow.replicas` | Number of Langflow replicas | `1` |
| `langflow.modelEndpoint` | LLM API endpoint URL | In-cluster KServe service |
| `postgresql.enabled` | Deploy PostgreSQL | `true` |
| `modelServing.enabled` | Deploy vLLM + KServe | `true` |
| `modelServing.modelName` | Model to serve | `meta-llama/Llama-3.1-8B-Instruct` |
| `modelServing.gpu.count` | GPUs for model serving | `1` |
| `mlflow.enabled` | Deploy MLflow tracking server | `true` |
| `mlflow.persistence.size` | MLflow artifact storage size | `10Gi` |
