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

### Inner Loop to Outer Loop (Production)

Develop locally, then package and deploy as a production API server.

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

# 5. Build a production container image (backend-only, no UI)
podman login quay.io
agentctl build --prod flows/my-flow.json quay.io/myorg v1.0

# 6. Deploy to OpenShift (picks up the built image automatically)
oc login https://your-cluster:6443
agentctl deploy --namespace my-agent-prod

# 7. Test the agent via API
curl -X POST https://<route>/api/v1/run/<flow-id> \
  -H "Content-Type: application/json" \
  -d '{"input_value": "Hello", "output_type": "chat", "input_type": "chat"}'

# Cleanup
agentctl destroy --namespace my-agent-prod
agentctl local-down
```

The `--prod` flag builds a **Langflow Runtime** image — a headless API server without the UI.
The generated `values-override.yaml` is automatically used by `agentctl deploy`.

## CLI Reference

All operations go through `agentctl`:

| Command | Description |
|---------|-------------|
| `agentctl local-up` | Start local dev environment |
| `agentctl local-down [--force]` | Stop local environment (`--force` cleans stuck containers) |
| `agentctl deploy [--namespace ns]` | Deploy full stack to OpenShift |
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
| `modelServing.modelName` | Model to serve | `meta-llama/Llama-3.1-8B-Instruct` |
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

## Notes

- Flows pulled from the cluster may contain model components pointing to cluster-internal URLs. When loading these locally, update the model endpoint in the Langflow UI to point to Ollama (`http://ollama:11434/v1`).
- Langfuse auto-provisioning (org, project, API keys) only runs on first database creation. If you need to reset, remove the PostgreSQL volume and restart.
- When pushing images to Quay.io or other registries, ensure the repository is **public** or create a pull secret on the cluster (`oc create secret docker-registry ...`).
- Images are built for `linux/amd64` by default to match typical OpenShift cluster architecture.