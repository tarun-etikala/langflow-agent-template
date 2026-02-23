#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

FLOW_FILE="${1:-}"
REGISTRY="${2:-quay.io/your-org}"
IMAGE_TAG="${3:-latest}"

if [ -z "$FLOW_FILE" ]; then
  echo "Usage: $0 <flow-json-file> [registry] [tag]"
  echo ""
  echo "Examples:"
  echo "  $0 flows/example-rag-flow.json"
  echo "  $0 flows/my-flow.json quay.io/myorg v1.0"
  echo ""
  echo "This script:"
  echo "  1. Takes a Langflow flow JSON file"
  echo "  2. Builds a container image with the flow baked in"
  echo "  3. Pushes it to a registry"
  echo "  4. The Helm chart on the cluster can then deploy this image"
  exit 1
fi

if [ ! -f "$FLOW_FILE" ]; then
  echo "Error: Flow file not found: $FLOW_FILE"
  exit 1
fi

FLOW_NAME=$(basename "$FLOW_FILE" .json)
IMAGE_NAME="$REGISTRY/langflow-$FLOW_NAME:$IMAGE_TAG"

echo "Exporting flow: $FLOW_FILE"
echo "Image: $IMAGE_NAME"
echo ""

# Create a temporary build context
BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

cp "$FLOW_FILE" "$BUILD_DIR/flow.json"

# Generate Containerfile with kagenti.* OCI metadata labels
cat > "$BUILD_DIR/Containerfile" << EOF
FROM docker.io/langflowai/langflow:latest

# kagenti metadata labels — makes this image discoverable by the platform
LABEL kagenti.type="agent"
LABEL kagenti.name="$FLOW_NAME"
LABEL kagenti.version="$IMAGE_TAG"
LABEL kagenti.framework="langflow"
LABEL kagenti.description="Langflow agent: $FLOW_NAME"

# Copy the flow into the Langflow config directory
COPY flow.json /app/flow.json

# Set environment variables for the flow
ENV LANGFLOW_LOAD_FLOWS_PATH=/app/flow.json
ENV LANGFLOW_AUTO_LOGIN=true

EXPOSE 7860
EOF

echo "Building container image..."
podman build -t "$IMAGE_NAME" -f "$BUILD_DIR/Containerfile" "$BUILD_DIR"

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

# Write values override so deploy-cluster.sh picks up this image automatically
OVERRIDE_FILE="$PROJECT_ROOT/values-override.yaml"
cat > "$OVERRIDE_FILE" << EOF
langflow:
  image: $IMAGE_NAME
EOF

echo ""
echo "Saved $OVERRIDE_FILE"
echo "Next step: ./scripts/deploy-cluster.sh"
