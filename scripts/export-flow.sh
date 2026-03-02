#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse flags
PROD_MODE=false
TARGET_NAMESPACE=""
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod) PROD_MODE=true; shift ;;
    --namespace|-n) TARGET_NAMESPACE="$2"; shift 2 ;;
    *) POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done

FLOW_FILE="${POSITIONAL_ARGS[0]:-}"
REGISTRY="${POSITIONAL_ARGS[1]:-quay.io/your-org}"
IMAGE_TAG="${POSITIONAL_ARGS[2]:-latest}"

if [ -z "$FLOW_FILE" ]; then
  echo "Usage: $0 [--prod] [-n <namespace>] <flow-json-file> [registry] [tag]"
  echo ""
  echo "Options:"
  echo "  --prod           Build for production (Langflow Runtime, backend-only, no UI)"
  echo "  -n, --namespace  Target namespace — rewrites model endpoints in the flow"
  echo ""
  echo "Examples:"
  echo "  $0 flows/my-flow.json quay.io/myorg v1.0                    # IDE mode (full UI)"
  echo "  $0 --prod -n my-ns flows/my-flow.json quay.io/myorg v1.0    # Production, target namespace"
  echo ""
  echo "This script:"
  echo "  1. Takes a Langflow flow JSON file"
  echo "  2. Rewrites model endpoints for the target namespace (if -n is given)"
  echo "  3. Builds a container image with the flow baked in"
  echo "  4. Pushes it to a registry"
  echo "  5. The Helm chart on the cluster can then deploy this image"
  exit 1
fi

if [ ! -f "$FLOW_FILE" ]; then
  echo "Error: Flow file not found: $FLOW_FILE"
  exit 1
fi

FLOW_NAME=$(basename "$FLOW_FILE" .json)
IMAGE_NAME="$REGISTRY/langflow-$FLOW_NAME:$IMAGE_TAG"

if [ "$PROD_MODE" = true ]; then
  MODE_LABEL="runtime"
  echo "Mode: PRODUCTION (Langflow Runtime — backend-only, no UI)"
else
  MODE_LABEL="ide"
  echo "Mode: IDE (full Langflow UI)"
fi
echo "Exporting flow: $FLOW_FILE"
echo "Image: $IMAGE_NAME"
echo ""

# Create a temporary build context
BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

cp "$FLOW_FILE" "$BUILD_DIR/flow.json"

# Rewrite model endpoints for target namespace
if [ -n "$TARGET_NAMESPACE" ]; then
  echo "Rewriting model endpoints for namespace: $TARGET_NAMESPACE"
  python3 -c "
import json, re, sys

MODEL_URL = 'http://qwen25-7b-instruct-predictor.$TARGET_NAMESPACE.svc.cluster.local:8080/v1'
MODEL_NAME = 'qwen25-7b-instruct'

with open('$BUILD_DIR/flow.json') as f:
    flow = json.load(f)

changed = False
for node in flow.get('data', {}).get('nodes', []):
    template = node.get('data', {}).get('node', {}).get('template', {})
    name = node.get('data', {}).get('node', {}).get('display_name', '?')

    # Rewrite api_base field (built-in OpenAI/Ollama components)
    if 'api_base' in template:
        old_val = template['api_base'].get('value', '')
        if old_val and ('ollama' in old_val or 'svc.cluster.local' in old_val or old_val):
            template['api_base']['value'] = MODEL_URL
            print(f'  Updated {name}: api_base -> {MODEL_URL}')
            changed = True
    if 'model_name' in template:
        old_val = template['model_name'].get('value', '')
        if old_val:
            template['model_name']['value'] = MODEL_NAME
            print(f'  Updated {name}: model_name -> {MODEL_NAME}')
            changed = True

    # Rewrite custom component code (vLLM component with hardcoded URLs)
    code = template.get('code', {}).get('value', '')
    if '.svc.cluster.local' in code:
        updated = re.sub(
            r'(predictor\.)[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.svc\.cluster\.local)',
            r'\g<1>$TARGET_NAMESPACE\3',
            code
        )
        if updated != code:
            template['code']['value'] = updated
            print(f'  Updated {name}: custom component code')
            changed = True

if changed:
    with open('$BUILD_DIR/flow.json', 'w') as f:
        json.dump(flow, f, indent=2)
else:
    print('  No model endpoints found to rewrite.')
"
  echo ""
fi

# Generate Containerfile with kagenti.* OCI metadata labels
cat > "$BUILD_DIR/Containerfile" << EOF
FROM docker.io/langflowai/langflow:1.7.1

# kagenti metadata labels — makes this image discoverable by the platform
LABEL kagenti.type="agent"
LABEL kagenti.name="$FLOW_NAME"
LABEL kagenti.version="$IMAGE_TAG"
LABEL kagenti.framework="langflow"
LABEL kagenti.mode="$MODE_LABEL"
LABEL kagenti.description="Langflow agent: $FLOW_NAME"

# Create directories
RUN mkdir -p /app/langflow-config-dir /app/flows

# Copy the flow into the image
COPY flow.json /app/flows/flow.json

# Set environment variables for the flow
ENV LANGFLOW_LOAD_FLOWS_PATH=/app/flows
ENV LANGFLOW_AUTO_LOGIN=true
ENV LANGFLOW_SKIP_AUTH_AUTO_LOGIN=true
ENV LANGFLOW_CONFIG_DIR=/app/langflow-config-dir
ENV LANGFLOW_LOG_ENV=container
EOF

# Add production-specific configuration
if [ "$PROD_MODE" = true ]; then
  cat >> "$BUILD_DIR/Containerfile" << 'EOF'

# Production: backend-only mode (no UI)
ENV LANGFLOW_BACKEND_ONLY=true

EXPOSE 7860
CMD ["langflow", "run", "--backend-only", "--host", "0.0.0.0", "--port", "7860"]
EOF
else
  cat >> "$BUILD_DIR/Containerfile" << 'EOF'

EXPOSE 7860
EOF
fi

echo "Building container image (linux/amd64)..."
podman build --platform linux/amd64 -t "$IMAGE_NAME" -f "$BUILD_DIR/Containerfile" "$BUILD_DIR"

echo ""
echo "Image built: $IMAGE_NAME"
echo ""

read -p "Push to registry? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Pushing to $REGISTRY..."
  podman push "$IMAGE_NAME"
  echo "Pushed."
else
  echo "Skipped push. To push later: podman push $IMAGE_NAME"
fi

echo ""
echo "Next step:"
echo "  agentctl deploy --image $IMAGE_NAME"
