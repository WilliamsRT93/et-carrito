#!/bin/bash
# Clúster ECS Fargate + namespace Service Connect + log groups + task definitions.
set -euo pipefail
cd "$(dirname "$0")"
source ./00-params.env
source ./secrets.env
source ./ids.env

echo "== Log groups CloudWatch =="
aws logs create-log-group --log-group-name "/ecs/${PROJECT}-front" 2>/dev/null || echo "ya existia /ecs/${PROJECT}-front"
aws logs create-log-group --log-group-name "/ecs/${PROJECT}-back" 2>/dev/null || echo "ya existia /ecs/${PROJECT}-back"

echo "== Cluster ECS =="
aws ecs describe-clusters --clusters "${PROJECT}-cluster" --query "clusters[0].clusterName" --output text 2>/dev/null | grep -q "${PROJECT}-cluster" \
  && echo "cluster ya existe" \
  || aws ecs create-cluster --cluster-name "${PROJECT}-cluster" --capacity-providers FARGATE FARGATE_SPOT >/dev/null
echo "CLUSTER=${PROJECT}-cluster"

# Nota: ECS Service Connect (Cloud Map) NO esta disponible en esta cuenta AWS Academy
# (servicediscovery:CreatePrivateDnsNamespace denegado). La comunicacion Front->Back
# se resuelve con reglas de listener del ALB por path ("/api/*" -> target group back),
# metodo explicitamente admitido por la rubrica ("DNS interno, servicios o ALB").

echo "== Task definition: ev3-back =="
cat > ../ecs/task-def-back.json <<EOF
{
  "family": "${PROJECT}-back",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "LabRole",
  "taskRoleArn": "LabRole",
  "containerDefinitions": [
    {
      "name": "${PROJECT}-back",
      "image": "${REPO_BACK}:latest",
      "essential": true,
      "portMappings": [
        { "name": "back-5000", "containerPort": 5000, "protocol": "tcp", "appProtocol": "http" }
      ],
      "environment": [
        { "name": "DB_HOST", "value": "${DB_PRIVATE_IP}" },
        { "name": "DB_PORT", "value": "5432" },
        { "name": "DB_NAME", "value": "${DB_NAME}" },
        { "name": "DB_USER", "value": "${DB_USER}" },
        { "name": "DB_PASSWORD", "value": "${DB_PASSWORD}" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${PROJECT}-back",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF
aws ecs register-task-definition --cli-input-json file://../ecs/task-def-back.json --query "taskDefinition.taskDefinitionArn" --output text

echo "== Task definition: ev3-front =="
cat > ../ecs/task-def-front.json <<EOF
{
  "family": "${PROJECT}-front",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "LabRole",
  "taskRoleArn": "LabRole",
  "containerDefinitions": [
    {
      "name": "${PROJECT}-front",
      "image": "${REPO_FRONT}:latest",
      "essential": true,
      "portMappings": [
        { "name": "front-80", "containerPort": 80, "protocol": "tcp", "appProtocol": "http" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${PROJECT}-front",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF
aws ecs register-task-definition --cli-input-json file://../ecs/task-def-front.json --query "taskDefinition.taskDefinitionArn" --output text

echo "Listo."
