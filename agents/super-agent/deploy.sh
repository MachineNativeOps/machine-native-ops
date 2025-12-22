#!/bin/bash
# SuperAgent Deployment Script

set -euo pipefail

# Configuration
ENVIRONMENT="${1:-dev}"  # Default to dev environment
IMAGE_NAME="axiom-system/super-agent"
DOCKERFILE="Dockerfile"

# Environment-specific configuration
case $ENVIRONMENT in
  dev)
    NAMESPACE="axiom-system-dev"
    IMAGE_TAG="${IMAGE_TAG:-dev-latest}"
    RESOURCE_PREFIX="dev-"
    ;;
  staging)
    NAMESPACE="axiom-system-staging"
    IMAGE_TAG="${IMAGE_TAG:-staging-v1.0.0}"
    RESOURCE_PREFIX="staging-"
    ;;
  prod)
    NAMESPACE="axiom-system"
    IMAGE_TAG="${IMAGE_TAG:-v1.0.0}"
    RESOURCE_PREFIX="prod-"
    ;;
  *)
    echo "❌ Invalid environment: $ENVIRONMENT"
    echo "Usage: $0 [dev|staging|prod]"
    exit 1
    ;;
esac

echo "🚀 Deploying AAPS SuperAgent to $ENVIRONMENT environment..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check if kustomize is available
if ! command -v kustomize &> /dev/null; then
    echo "⚠️  kustomize is not installed, falling back to kubectl kustomize"
    KUSTOMIZE_CMD="kubectl kustomize"
else
    KUSTOMIZE_CMD="kustomize build"
fi

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed or not in PATH"
    exit 1
fi

# Build Docker image
echo "📦 Building Docker image..."
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
if [ $? -ne 0 ]; then
    echo "❌ Docker build failed"
    exit 1
fi

# Test Docker image
echo "🧪 Testing Docker image..."
docker run --rm -d -p 8080:8080 --name super-agent-test ${IMAGE_NAME}:${IMAGE_TAG}

# Wait for container to start
echo "⏳ Waiting for SuperAgent to start..."
sleep 10

# Test health endpoint
echo "🔍 Testing health endpoint..."
if curl -f http://localhost:8080/health > /dev/null 2>&1; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed"
    docker stop super-agent-test
    exit 1
fi

# Ensure python3 and dependencies are available before running integration tests
if ! command -v python3 &> /dev/null; then
    echo "❌ python3 is not installed or not in PATH"
    docker stop super-agent-test
    docker rm super-agent-test
    exit 1
fi

echo "📦 Ensuring Python dependencies for integration tests..."
if ! python3 -m pip show requests > /dev/null 2>&1; then
    if ! python3 -m pip install --user requests > /dev/null 2>&1; then
        echo "❌ Failed to install Python dependency 'requests'"
        docker stop super-agent-test
        docker rm super-agent-test
        exit 1
    fi
fi
# Run integration tests
echo "🧪 Running integration tests..."
python3 test_super_agent.py http://localhost:8080
TEST_RESULT=$?

# Stop test container
docker stop super-agent-test
docker rm super-agent-test

if [ $TEST_RESULT -ne 0 ]; then
    echo "❌ Integration tests failed"
    exit 1
fi

echo "✅ Docker image and tests passed"

# Deploy to Kubernetes
echo "🚀 Deploying to Kubernetes using Kustomize..."
# Create temporary directory for kustomize with dynamic image tag
TMP_KUSTOMIZE_DIR="$(mktemp -d)"
cp -R "overlays/${ENVIRONMENT}/" "${TMP_KUSTOMIZE_DIR}/"
cp -R "base/" "${TMP_KUSTOMIZE_DIR}/base/"

(
  cd "${TMP_KUSTOMIZE_DIR}" || exit 1
  # Update image tag to match IMAGE_TAG environment variable
  if command -v kustomize &> /dev/null; then
    kustomize edit set image "${IMAGE_NAME}=${IMAGE_NAME}:${IMAGE_TAG}"
  else
    # Fallback: manually update kustomization.yaml
    sed -i "s|newTag:.*|newTag: ${IMAGE_TAG}|g" kustomization.yaml
  fi
  $KUSTOMIZE_CMD .
) | kubectl apply -f -

# Cleanup temporary directory
rm -rf "${TMP_KUSTOMIZE_DIR}"

# Wait for deployment
echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/${RESOURCE_PREFIX}super-agent -n ${NAMESPACE}

# Verify deployment
echo "✅ Verifying deployment..."
kubectl get pods -n ${NAMESPACE} -l app=super-agent
kubectl get services -n ${NAMESPACE} -l app=super-agent

# Test the deployed service
echo "🔍 Testing deployed service..."
SUPER_AGENT_IP=$(kubectl get svc ${RESOURCE_PREFIX}super-agent -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')

if [ -n "$SUPER_AGENT_IP" ] && [ "$SUPER_AGENT_IP" != "<none>" ]; then
    echo "🌐 Testing service at http://$SUPER_AGENT_IP:8080"
    
    # Wait a moment for service to be fully ready
    sleep 5
    
    if curl -f http://$SUPER_AGENT_IP:8080/health > /dev/null 2>&1; then
        echo "✅ Service health check passed"
        
        # Run integration tests against deployed service
        echo "🧪 Running integration tests against deployed service..."
        python3 test_super_agent.py http://$SUPER_AGENT_IP:8080
        
        if [ $? -eq 0 ]; then
            echo "✅ Integration tests passed"
        else
            echo "⚠️  Integration tests had issues, but deployment succeeded"
        fi
    else
        echo "❌ Service health check failed"
        echo "🔍 Checking pod logs..."
        kubectl logs -n ${NAMESPACE} -l app=super-agent --tail=20
        exit 1
    fi
else
    echo "⚠️  Could not get service IP (might be using NodePort or LoadBalancer)"
fi

echo ""
echo "🎉 SuperAgent deployment completed successfully!"
echo ""
echo "📋 Service Information:"
echo "  Environment: ${ENVIRONMENT}"
echo "  Namespace: ${NAMESPACE}"
echo "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  Service: ${RESOURCE_PREFIX}super-agent.${NAMESPACE}.svc.cluster.local:8080"
echo ""
echo "🔍 Useful Commands:"
echo "  Check pods: kubectl get pods -n ${NAMESPACE} -l app=super-agent"
echo "  View logs: kubectl logs -n ${NAMESPACE} -l app=super-agent -f"
echo "  Port forward: kubectl port-forward -n ${NAMESPACE} svc/${RESOURCE_PREFIX}super-agent 8080:8080"
echo "  Test locally: python3 test_super_agent.py http://localhost:8080"
echo ""
echo "🔧 Kustomize Commands:"
echo "  Preview changes: kustomize build overlays/${ENVIRONMENT}"
echo "  Apply directly: kustomize build overlays/${ENVIRONMENT} | kubectl apply -f -"
echo ""
echo "📚 Documentation: ./README.md"