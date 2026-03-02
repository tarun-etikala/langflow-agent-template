# CLAUDE.md

## Project Overview

Langflow Agent Template — a template for building, testing, and deploying Langflow-based AI agents. Supports local development (Podman) and cluster deployment (OpenShift via Helm).

## Architecture

Two deployment targets with equivalent stacks:

- **Local**: Langflow + PostgreSQL + Ollama + Langfuse via `podman-compose`
- **Cluster**: Langflow + PostgreSQL (Red Hat) + Langfuse + vLLM/KServe via Helm on OpenShift

The `flows/` directory is the Git-trackable hub for portable flow definitions.

## Project Structure

```
langflow-agent-template/
├── scripts/agentctl              # Main CLI tool (all commands)
├── scripts/deploy-local.sh       # Called by agentctl local-up
├── scripts/export-flow.sh        # Called by agentctl build
├── local/
│   ├── podman-compose.yml        # Local stack: langflow, postgres, ollama, langfuse
│   ├── init-db.sh                # Creates langfuse database on postgres startup
│   └── .env.example
├── helm/langflow-agent/
│   ├── Chart.yaml
│   ├── values.yaml               # All configurable values
│   └── templates/
│       ├── _helpers.tpl           # postgresUrl helper, labels
│       ├── langflow.yaml          # Deployment + PVC + Service + Route
│       ├── postgresql.yaml        # Red Hat PostgreSQL 15 + Secret + PVC
│       ├── langfuse.yaml          # Langfuse v2 + initContainer for DB creation
│       ├── langfuse-secret.yaml   # Shared credentials (Langfuse <-> Langflow)
│       └── charts/model-serving/  # vLLM + KServe subchart (disabled by default)
└── flows/                         # Exported flow JSON files
```

## Key Commands

All operations go through `agentctl` (add `scripts/` to PATH):

```bash
agentctl local-up                  # Start local dev environment
agentctl local-down [--force]      # Stop local (--force removes volumes too)
agentctl deploy [--image img] [-n ns]  # Deploy to OpenShift (--image uses built image, without it pulls default from Docker Hub)
agentctl destroy [--namespace ns]  # Remove all cluster resources
agentctl flows save                # Local Langflow -> flows/ dir
agentctl flows load                # flows/ dir -> Local Langflow
agentctl flows pull [-n ns]        # Cluster Langflow -> flows/ dir
agentctl flows push [-n ns]        # flows/ dir -> Cluster Langflow
agentctl build [--prod] <flow.json> [reg] [tag]  # Build flow image (--prod for API-only runtime)
agentctl list [--all-namespaces]   # List deployed agents
agentctl status <name> [-n ns]     # Show agent status
```

## Key Patterns

### Langfuse Auto-Provisioning
Both local and cluster use `LANGFUSE_INIT_*` env vars to auto-create org, project, user, and API keys on first boot. No manual Langfuse UI setup needed. Credentials are shared via:
- Local: matching env vars in `podman-compose.yml`
- Cluster: Kubernetes Secret (`langfuse-secret.yaml`) referenced by both Langfuse and Langflow deployments

### Database Initialization
- Langfuse database is created via `initContainer` (cluster) or `init-db.sh` (local)
- Langflow database ownership fixed via `initContainer` running `ALTER DATABASE OWNER TO`
- PostgreSQL on cluster uses Red Hat image (`registry.redhat.io/rhel9/postgresql-15:latest`), not Bitnami

### OpenShift-Specific
- Langflow HOME redirected to `/app/data` (PVC) because OpenShift restricted SCC blocks `/var/lib/langflow`
- `emptyDir` volumes for `/tmp` and `/.cache`
- Strategy: Recreate (not rolling) for Langflow deployment
- Routes with TLS edge termination

### Flow Sync
- `flows save/pull` strips environment-specific fields (`id`, `user_id`, `folder_id`, `updated_at`, `created_at`) for portability
- `flows push/load` uploads via `POST /api/v1/flows/upload/` (multipart file)
- Auth via `POST /api/v1/login` with default credentials `langflow/langflow`

### Build & Deploy
- `agentctl build <flow.json> [registry] [tag]` — builds full Langflow image (UI + flow baked in)
- `agentctl build --prod` — builds **Langflow Runtime** image (backend-only, no UI)
- `-n <namespace>` on build rewrites model endpoints (api_base, model_name) in the flow JSON to point to the cluster's KServe URL
- Images are built for `linux/amd64` via `podman build --platform linux/amd64`
- `agentctl deploy --image <img>` — deploys with the built image
- `agentctl deploy` (no `--image`) — no image is built or pushed; OpenShift pulls the default Langflow image from Docker Hub. Use `agentctl flows push` to upload flows after deploy.
- The Helm template conditionally sets `LANGFLOW_BACKEND_ONLY=true` and `LANGFLOW_SKIP_AUTH_AUTO_LOGIN=true`
- `LANGFLOW_LOAD_FLOWS_PATH` must point to a **directory** (not a file) — Langflow calls `iterdir()` on it
- `LANGFLOW_SKIP_AUTH_AUTO_LOGIN=true` is required for Langflow >= 1.5 to allow unauthenticated API access with auto-login
- Registry images must be public or the cluster needs a pull secret

### Custom vLLM Component
Flows using the cluster's model serving have a custom `VLLMModel` component with hardcoded `base_url`. When moving flows between environments, the model endpoint URL must be changed:
- Local: `http://ollama:11434/v1` with model `qwen2.5:7b`
- Cluster: `http://qwen25-7b-instruct-predictor.<namespace>.svc.cluster.local:8080/v1` with model `qwen25-7b-instruct`

## Known Issues

- `flows push`/`flows load` creates duplicates if the flow already exists on the target
- Langfuse INIT vars only run on first database creation — if the database already exists from a prior run, wipe volumes and restart

## Images Used

- Langflow: `docker.io/langflowai/langflow:1.7.1`
- PostgreSQL (cluster): `registry.redhat.io/rhel9/postgresql-15:latest`
- PostgreSQL (local): `docker.io/library/postgres:15`
- Langfuse: `quay.io/rh-ee-mpk/langfuse:2-amd64` (cluster), `docker.io/langfuse/langfuse:2` (local)
- Ollama: `docker.io/ollama/ollama:latest`
- vLLM: `registry.redhat.io/rhaiis/vllm-cuda-rhel9` (specific SHA digest)

## Default Credentials

- **Langflow**: auto-login (no credentials needed)
- **Langfuse local**: `admin@langflow.local` / `admin123`, API keys `pk-lf-local-dev` / `sk-lf-local-dev`
- **Langfuse cluster**: `admin@langflow.local` / `admin123`, API keys `pk-lf-langflow-agent` / `sk-lf-langflow-agent`
- **PostgreSQL**: `langflow` / `langflow`, database `langflow`