#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$PROJECT_ROOT/helm/langflow-agent"
RELEASE_NAME="${1:-langflow-agent}"
NAMESPACE="${2:-langflow-agent}"

# Verify we're logged into a cluster
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged into an OpenShift cluster."
  echo "Run: oc login <cluster-url>"
  exit 1
fi

CLUSTER=$(oc whoami --show-server)
echo "Deploying to cluster: $CLUSTER"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo ""

# Create namespace if it doesn't exist
oc get namespace "$NAMESPACE" &>/dev/null || oc new-project "$NAMESPACE"

# Update Helm dependencies (downloads Bitnami PostgreSQL chart)
echo "Updating Helm dependencies..."
helm dependency update "$CHART_DIR"

# Check for values override from export-flow.sh
OVERRIDE_FILE="$PROJECT_ROOT/values-override.yaml"
OVERRIDE_FLAG=""
if [ -f "$OVERRIDE_FILE" ]; then
  echo "Found values-override.yaml — using exported flow image."
  OVERRIDE_FLAG="-f $OVERRIDE_FILE"
fi

# Install or upgrade the chart
echo "Installing/upgrading Helm release..."
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  $OVERRIDE_FLAG \
  --wait \
  --timeout 10m

echo ""
echo "Deployment complete. Checking status..."
helm status "$RELEASE_NAME" -n "$NAMESPACE"

echo ""
echo "Routes:"
oc get routes -n "$NAMESPACE" -o custom-columns='NAME:.metadata.name,HOST:.spec.host'

echo ""
echo "Run 'helm test $RELEASE_NAME -n $NAMESPACE' to validate the deployment."
