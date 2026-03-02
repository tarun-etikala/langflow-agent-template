#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOCAL_DIR="$PROJECT_ROOT/local"

# Copy .env if it doesn't exist
if [ ! -f "$LOCAL_DIR/.env" ]; then
  cp "$LOCAL_DIR/.env.example" "$LOCAL_DIR/.env"
  echo "Created .env from .env.example — edit it if needed."
fi

# Ask about Ollama on first run
OLLAMA_FLAG="$LOCAL_DIR/.ollama-enabled"
if [ ! -f "$OLLAMA_FLAG" ]; then
  echo ""
  read -p "Do you want to use Ollama as a local LLM? (Y/n) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "yes" > "$OLLAMA_FLAG"
  else
    echo "no" > "$OLLAMA_FLAG"
    echo "Ollama disabled. You can point Langflow to an external model endpoint instead."
  fi
fi

USE_OLLAMA=$(cat "$OLLAMA_FLAG")

cd "$LOCAL_DIR"

# Start all services
echo ""
echo "Starting local development environment..."
podman-compose up -d

echo ""
echo "Waiting for services to start..."
sleep 10

# Pull Ollama model only if enabled and not already downloaded
if [ "$USE_OLLAMA" = "yes" ]; then
  # Source .env to get OLLAMA_MODEL if set
  if [ -f "$LOCAL_DIR/.env" ]; then
    OLLAMA_MODEL=$(grep -E '^OLLAMA_MODEL=' "$LOCAL_DIR/.env" | cut -d= -f2-)
  fi
  OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:7b}"
  OLLAMA_CONTAINER=$(podman ps --filter "name=ollama" --format "{{.Names}}" | head -1)

  # Check if model is already pulled
  if podman exec "$OLLAMA_CONTAINER" ollama list 2>/dev/null | grep -q "$OLLAMA_MODEL"; then
    echo "Ollama model '$OLLAMA_MODEL' already available."
  else
    echo "Pulling Ollama model: $OLLAMA_MODEL (first time only)..."
    podman exec -it "$OLLAMA_CONTAINER" ollama pull "$OLLAMA_MODEL" || \
      echo "Warning: Could not pull model. Run manually: podman exec -it $OLLAMA_CONTAINER ollama pull $OLLAMA_MODEL"
  fi
fi

echo ""
echo "Local environment is ready."
echo ""
echo "  Langflow UI:  http://localhost:7860"
echo "  Langfuse:     http://localhost:3000  (login: admin@langflow.local / admin123)"
if [ "$USE_OLLAMA" = "yes" ]; then
  echo "  Ollama API:   http://localhost:11434"
fi
echo ""
echo "  ⚠  If your flow was pulled from the cluster, update the model component:"
echo "     Langflow UI > click model component > change api_base and model_name"
echo ""
echo "  Model endpoint:"
echo "    Local (Ollama):   api_base=http://ollama:11434/v1  model_name=qwen2.5:7b"
echo "    Cluster (vLLM):   api_base=<KServe InferenceService URL>/v1  model_name=qwen25-7b-instruct"