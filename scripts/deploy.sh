#!/usr/bin/env bash
# Build the orders image, push it to ECR tagged with the git SHA, and deploy it to EKS.
#
# Usage:  scripts/deploy.sh                 (from the orders-app repo root, in Git Bash / Linux / macOS)
# Env:    CLUSTER_NAME (default: gateway)   EKS cluster name; kubectl's context must point at it
#         AWS_REGION   (default: us-east-2)
#         ECR_REPO     (default: <account>.dkr.ecr.<region>.amazonaws.com/orders)
#         ALLOW_DIRTY=1                     deploy even with uncommitted changes (tag gets a -dirty suffix)
set -euo pipefail

# --- 1. Safety first: which cluster is kubectl pointed at? ---------------------------------------
CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
echo "kubectl current-context: ${CONTEXT:-<none>}"

CLUSTER_NAME="${CLUSTER_NAME:-gateway}"
AWS_REGION="${AWS_REGION:-us-east-2}"

# EKS contexts from `aws eks update-kubeconfig` are "arn:aws:eks:<region>:<account>:cluster/<name>".
# Require that exact suffix: a substring match alone would also accept e.g. "gateway-prod" or "my-gateway".
if [[ "$CONTEXT" != *":cluster/${CLUSTER_NAME}" ]]; then
  echo "ABORT: current context does not contain EKS cluster '${CLUSTER_NAME}' (expected ...:cluster/${CLUSTER_NAME})." >&2
  echo "       Run: aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}" >&2
  exit 1
fi

# --- 2. Work out the image tag -----------------------------------------------------------------
cd "$(dirname "$0")/.."   # repo root, wherever the script is called from
SHA="$(git rev-parse HEAD)"
TAG="$SHA"
if [[ -n "$(git status --porcelain)" ]]; then
  if [[ "${ALLOW_DIRTY:-0}" != "1" ]]; then
    echo "ABORT: uncommitted changes; the image tag wouldn't match the code. Commit first, or set ALLOW_DIRTY=1." >&2
    exit 1
  fi
  TAG="${SHA}-dirty"
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REPO="${ECR_REPO:-${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/orders}"
REGISTRY="${ECR_REPO%%/*}"
IMAGE="${ECR_REPO}:${TAG}"
echo "Deploying ${IMAGE}"

# --- 3. Log in to ECR, build, push ----------------------------------------------------------------
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"
# Nodes are x86_64 (t3.small); build for that even on an ARM laptop.
docker build --platform linux/amd64 -t "$IMAGE" .
docker push "$IMAGE"

# --- 4. Substitute ORDERS_IMAGE and apply ---------------------------------------------------------
RENDERED="$(mktemp -d)"
trap 'rm -rf "$RENDERED"' EXIT
for f in namespace.yaml deployment.yaml service.yaml; do
  sed "s|ORDERS_IMAGE|${IMAGE}|g" "k8s/$f" > "$RENDERED/$f"
done
if grep -q ORDERS_IMAGE "$RENDERED"/*.yaml; then
  echo "ABORT: ORDERS_IMAGE placeholder still present after substitution." >&2
  exit 1
fi

kubectl apply -f "$RENDERED/namespace.yaml"
kubectl apply -f "$RENDERED/deployment.yaml" -f "$RENDERED/service.yaml"

# --- 5. Wait for the rollout ---------------------------------------------------------------------
kubectl -n orders rollout status deployment/orders --timeout=180s
kubectl -n orders get pods -l app.kubernetes.io/name=orders -o wide
echo "Deployed ${IMAGE}"
