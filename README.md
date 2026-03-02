# Langflow Agent Template

A template for building, testing, and deploying Langflow-based AI agents on OpenShift. Provides identical stacks for local development and cluster deployment, with CLI tooling to move flows between environments.

## Architecture

```
LOCAL (podman-compose)                    CLUSTER (Helm + OpenShift)
┌──────────────────────────┐              ┌──────────────────────────┐
│  Langflow UI  :7860      │              │  Langflow (Deployment)   │
│         │                │              │         │                │
│         ▼                │   flows/     │         ▼                │
│  Ollama :11434           │ ◄──────────► │  vLLM + KServe           │
│  (local LLM)             │   (Git)      │  (GPU model serving)     │
│         │                │              │         │                │
│         ▼                │              │         ▼                │
│  PostgreSQL :5432        │              │  PostgreSQL (Red Hat)    │
│         │                │              │         │                │
│         ▼                │              │         ▼                │
│  Langfuse :3000          │              │  Langfuse (Deployment)   │
│  (tracing)               │              │  (tracing)               │
└──────────────────────────┘              └──────────────────────────┘
```

The `flows/` directory is the Git-trackable hub. Flows are exported as portable JSON files that can be synced between local and cluster environments.

## Project Structure

```
langflow-agent-template/
├── scripts/
│   └── agentctl                   # CLI tool — all operations go through this
│
├── local/
│   ├── podman-compose.yml         # Langflow + PostgreSQL + Ollama + Langfuse
│   ├── init-db.sh                 # Creates langfuse database on first boot
│   └── .env.example               # Environment variables
│
├── helm/langflow-agent/
│   ├── Chart.yaml                 # Helm chart metadata
│   ├── values.yaml                # All configurable values
│   └── templates/
│       ├── langflow.yaml          # Langflow Deployment + Service + Route
│       ├── postgresql.yaml        # PostgreSQL Deployment + Secret + PVC
│       ├── langfuse.yaml          # Langfuse Deployment + Service + Route
│       ├── langfuse-secret.yaml   # Shared credentials (Langfuse <-> Langflow)
│       └── charts/model-serving/  # vLLM + KServe subchart (disabled by default)
│
└── flows/                         # Portable flow JSON files
    ├── demo-flow-v1.json
    └── ...
```

## Prerequisites

- **Local**: Podman + podman-compose (auto-installed by `agentctl` on macOS/Linux if missing)
- **Cluster**: `oc` CLI + `helm` CLI + access to an OpenShift cluster with RHOAI installed

## Setup

Add `agentctl` to your PATH:

```bash
export PATH="$PATH:$(pwd)/scripts"
```

### Start Podman Machine

The Podman machine must be running before using `agentctl local-up`. If it's not already started:

```bash
podman machine start
```

To check its status:

```bash
podman machine list
```

**Memory**: The Podman VM needs at least 8GB of memory. If it's set lower, increase it:

```bash
podman machine stop
podman machine set --memory 8192
podman machine start
```

**Platform**: The `platform` field in `local/podman-compose.yml` must match your machine's architecture. Update it if needed:

| Machine | Platform |
|---------|----------|
| Mac (Apple Silicon) | `linux/arm64` |
| Mac (Intel) | `linux/amd64` |
| Linux (x86_64) | `linux/amd64` |

### Cluster Login

To get the `oc login` command for your cluster:

1. Open the OpenShift web console in your browser
2. Click your username in the top-right corner
3. Click **Copy login command**
4. Click **Display Token**
5. Copy the `oc login` command and run it in your terminal:

```bash
oc login --token=sha256~XXXX --server=https://api.your-cluster.example.com:6443
```

## Workflows

### Local-First

Build and test your agent locally, then push to the cluster.

```bash
# 1. Start local environment (Langflow + PostgreSQL + Ollama + Langfuse)
agentctl local-up

# 2. Build your agent flow in the Langflow UI
open http://localhost:7860

# 3. Run the flow and verify traces in Langfuse
open http://localhost:3000    # Login: admin@langflow.local / admin123

# 4. Save flows from local Langflow to the flows/ directory
agentctl flows save

# 5. Commit flows to Git
git add flows/ && git commit -m "Add agent flow"

# 6. Deploy the full stack to OpenShift
oc login https://your-cluster:6443
agentctl deploy

# 7. Push flows to the cluster Langflow instance
agentctl flows push

# 8. Open the flow in cluster Langflow and verify it works
#    (URL printed by agentctl deploy)

# Cleanup
agentctl destroy              # Remove cluster resources
agentctl local-down           # Stop local environment
```

### Cloud-First

Build your agent on the cluster, then pull to local for iteration.

```bash
# 1. Deploy the full stack to OpenShift
oc login https://your-cluster:6443
agentctl deploy

# 2. Build your agent flow in the cluster Langflow UI
#    (URL printed by agentctl deploy)

# 3. Run the flow and verify traces in cluster Langfuse

# 4. Pull flows from cluster Langflow to the flows/ directory
agentctl flows pull

# 5. Commit flows to Git
git add flows/ && git commit -m "Add agent flow"

# 6. Start local environment for iteration
agentctl local-up

# 7. Load flows into local Langflow
agentctl flows load

# 8. Open the flow in local Langflow
open http://localhost:7860

# Cleanup
agentctl destroy              # Remove cluster resources
agentctl local-down           # Stop local environment
```

### Build & Deploy (Production)

Develop locally, then package and deploy as a container image.

```bash
# ── Inner Loop (Development) ──────────────────────────

# 1. Start local environment
agentctl local-up

# 2. Build and test your agent flow in the Langflow UI
open http://localhost:7860

# 3. Save flows to the flows/ directory
agentctl flows save

# 4. Commit flows to Git
git add flows/ && git commit -m "Add agent flow"

# ── Outer Loop (Production) ──────────────────────────

# 5. Build a container image with the flow baked in
podman login quay.io
agentctl build flows/my-flow.json quay.io/myorg v1.0             # full UI
agentctl build --prod flows/my-flow.json quay.io/myorg v1.0      # headless API only

# 6. Deploy to OpenShift with the built image
oc login https://your-cluster:6443
agentctl deploy --image quay.io/myorg/langflow-my-flow:v1.0

# 7. Test the agent via API (URL printed by deploy)
curl -X POST https://<route>/api/v1/run/<flow-id> \
  -H "Content-Type: application/json" \
  -d '{"input_value": "Hello", "output_type": "chat", "input_type": "chat"}'

# Cleanup
agentctl destroy
agentctl local-down
```

- `agentctl build`: builds a full Langflow image with UI + flow baked in
- `agentctl build --prod`: builds a **Langflow Runtime** image — headless API server, no UI
- `agentctl deploy --image`: deploys with your built image
- `agentctl deploy` (no `--image`): no image is built or pushed — OpenShift pulls the default Langflow image directly from Docker Hub. Use `agentctl flows push` to upload your flows after deploy.

> **Note:** `agentctl build` will create a new repository in Quay.io when pushing. The repository defaults to **private**. You need to make it **public** in the Quay.io UI so that OpenShift can pull the image without a pull secret.

## CLI Reference

All operations go through `agentctl`:

| Command | Description |
|---------|-------------|
| `agentctl local-up` | Start local dev environment |
| `agentctl local-down [--force]` | Stop local environment (`--force` removes volumes too) |
| `agentctl deploy [--image img] [--namespace ns]` | Deploy full stack to OpenShift |
| `agentctl destroy [--namespace ns]` | Remove all cluster resources |
| `agentctl flows save` | Local Langflow &rarr; `flows/` directory |
| `agentctl flows load` | `flows/` directory &rarr; Local Langflow |
| `agentctl flows pull [-n ns]` | Cluster Langflow &rarr; `flows/` directory |
| `agentctl flows push [-n ns]` | `flows/` directory &rarr; Cluster Langflow |
| `agentctl build [--prod] <flow.json> [registry] [tag]` | Build flow into a container image (`--prod` for API-only runtime) |
| `agentctl list [--all-namespaces]` | List deployed agents |
| `agentctl status <name> [-n ns]` | Show agent status and metadata |

## Configuration

### Helm Values

Key values in `helm/langflow-agent/values.yaml`:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `langflow.image` | Langflow container image | `langflowai/langflow:1.7.1` |
| `langflow.replicas` | Number of Langflow replicas | `1` |
| `langflow.backendOnly` | Run as Langflow Runtime (API-only, no UI) | `false` |
| `langfuse.enabled` | Deploy Langfuse for tracing | `true` |
| `modelServing.enabled` | Deploy vLLM + KServe | `false` |
| `modelServing.modelName` | Model to serve | `Qwen/Qwen2.5-7B-Instruct` |
| `modelServing.gpu.count` | GPUs for model serving | `1` |

### Deploy with Model Serving

```bash
agentctl deploy --no-model-serving    # Without GPU model serving (default)
```

To enable model serving, set `modelServing.enabled: true` in `values.yaml`. Requires a GPU node and KServe/RHOAI on the cluster.

## Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| Langflow | (auto-login) | |
| Langfuse (local) | admin@langflow.local | admin123 |
| Langfuse (cluster) | admin@langflow.local | admin123 |
| PostgreSQL | langflow | langflow |

## Services & Ports (Local)

| Service | URL |
|---------|-----|
| Langflow UI | http://localhost:7860 |
| Langfuse | http://localhost:3000 |
| Ollama API | http://localhost:11434 |

## Using a Third-Party Model (OpenAI, Anthropic, etc.)

You don't need Ollama or vLLM if you want to use a third-party model provider. Just configure the model component directly in the Langflow UI:

1. Open your flow in Langflow
2. Use a built-in **OpenAI** / **Anthropic** / **OpenAI-compatible** component
3. Set `api_base` to the provider's URL and `api_key` to your key

This works the same locally and on cluster — no infrastructure changes needed.

Alternatively, set the model endpoint in `local/.env`:

```bash
OPENAI_API_BASE=https://api.openai.com/v1
OPENAI_API_KEY=sk-...
```

## Notes

- Flows pulled from the cluster may contain model components pointing to cluster-internal URLs. When loading these locally, update the model endpoint in the Langflow UI to point to Ollama (`http://ollama:11434/v1`).
- Langfuse auto-provisioning (org, project, API keys) only runs on first database creation. If you need to reset, remove the PostgreSQL volume and restart.
- When pushing images to Quay.io or other registries, ensure the repository is **public** or create a pull secret on the cluster (`oc create secret docker-registry ...`).
- Images are built for `linux/amd64` by default to match typical OpenShift cluster architecture.