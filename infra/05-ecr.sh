#!/bin/bash
# Crea los repositorios ECR y construye/publica las imagenes de front y back.
set -euo pipefail
cd "$(dirname "$0")"
source ./00-params.env
source ./ids.env

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo "REGISTRY=$REGISTRY"

get_or_create_repo() {
  local name="$1"
  aws ecr describe-repositories --repository-names "$name" --query "repositories[0].repositoryUri" --output text 2>/dev/null \
    || aws ecr create-repository --repository-name "$name" --image-scanning-configuration scanOnPush=true \
         --query "repository.repositoryUri" --output text
}

echo "== Repositorios ECR =="
REPO_FRONT=$(get_or_create_repo "${PROJECT}-front")
echo "REPO_FRONT=$REPO_FRONT"
REPO_BACK=$(get_or_create_repo "${PROJECT}-back")
echo "REPO_BACK=$REPO_BACK"

echo "== Login a ECR =="
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

echo "== Build + push frontend =="
docker build -t "$REPO_FRONT:latest" "../frontend"
docker push "$REPO_FRONT:latest"

echo "== Build + push backend =="
docker build -t "$REPO_BACK:latest" "../backend"
docker push "$REPO_BACK:latest"

grep -v "^export REPO_FRONT=\|^export REPO_BACK=\|^export ACCOUNT_ID=\|^export REGISTRY=" ./ids.env > ./ids.env.tmp || true
mv ./ids.env.tmp ./ids.env
cat >> ./ids.env <<EOF
export ACCOUNT_ID="$ACCOUNT_ID"
export REGISTRY="$REGISTRY"
export REPO_FRONT="$REPO_FRONT"
export REPO_BACK="$REPO_BACK"
EOF
echo "Listo."
