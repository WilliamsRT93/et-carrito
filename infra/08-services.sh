#!/bin/bash
# Servicios ECS Fargate: ev3-svc-front (detras del ALB) y ev3-svc-back (interno via Service Connect).
set -euo pipefail
cd "$(dirname "$0")"
source ./00-params.env
source ./ids.env

echo "== Servicio backend (detras del ALB, regla de path /api/*) =="
aws ecs describe-services --cluster "${PROJECT}-cluster" --services "${PROJECT}-svc-back" \
  --query "services[0].status" --output text 2>/dev/null | grep -q "ACTIVE" && BACK_EXISTS=1 || BACK_EXISTS=0

if [ "$BACK_EXISTS" == "0" ]; then
  aws ecs create-service \
    --cluster "${PROJECT}-cluster" \
    --service-name "${PROJECT}-svc-back" \
    --task-definition "${PROJECT}-back" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_PUB_1A,$SUBNET_PUB_1B],securityGroups=[$SG_BACK],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=$TG_BACK_ARN,containerName=${PROJECT}-back,containerPort=5000" \
    --query "service.serviceArn" --output text
else
  echo "ev3-svc-back ya existe"
fi

echo "== Servicio frontend (publico via ALB) =="
aws ecs describe-services --cluster "${PROJECT}-cluster" --services "${PROJECT}-svc-front" \
  --query "services[0].status" --output text 2>/dev/null | grep -q "ACTIVE" && FRONT_EXISTS=1 || FRONT_EXISTS=0

if [ "$FRONT_EXISTS" == "0" ]; then
  aws ecs create-service \
    --cluster "${PROJECT}-cluster" \
    --service-name "${PROJECT}-svc-front" \
    --task-definition "${PROJECT}-front" \
    --desired-count 2 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_PUB_1A,$SUBNET_PUB_1B],securityGroups=[$SG_FRONT],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=$TG_FRONT_ARN,containerName=${PROJECT}-front,containerPort=80" \
    --query "service.serviceArn" --output text
else
  echo "ev3-svc-front ya existe"
fi

echo "== Esperando estabilidad de los servicios (puede tardar 1-3 min) =="
aws ecs wait services-stable --cluster "${PROJECT}-cluster" --services "${PROJECT}-svc-back" "${PROJECT}-svc-front"
echo "Servicios estables."

aws ecs describe-services --cluster "${PROJECT}-cluster" --services "${PROJECT}-svc-back" "${PROJECT}-svc-front" \
  --query "services[].{Servicio:serviceName,Deseadas:desiredCount,Corriendo:runningCount,Estado:status}" --output table
