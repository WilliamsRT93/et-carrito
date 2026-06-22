#!/bin/bash
# Application Auto Scaling: Target Tracking CPU 50% para ambos servicios ECS.
set -euo pipefail
cd "$(dirname "$0")"
source ./00-params.env

register_and_scale() {
  local svc="$1"
  local resource_id="service/${PROJECT}-cluster/${svc}"

  echo "== Registrando scalable target: $resource_id (min 1 / max 4) =="
  aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id "$resource_id" \
    --scalable-dimension ecs:service:DesiredCount \
    --min-capacity 1 --max-capacity 4

  echo "== Politica Target Tracking CPU 50% para $svc =="
  aws application-autoscaling put-scaling-policy \
    --service-namespace ecs \
    --resource-id "$resource_id" \
    --scalable-dimension ecs:service:DesiredCount \
    --policy-name "${svc}-cpu50-target-tracking" \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration '{
      "TargetValue": 50.0,
      "PredefinedMetricSpecification": {"PredefinedMetricType": "ECSServiceAverageCPUUtilization"},
      "ScaleInCooldown": 60,
      "ScaleOutCooldown": 60
    }' --query "PolicyARN" --output text
}

register_and_scale "${PROJECT}-svc-back"
register_and_scale "${PROJECT}-svc-front"

echo "== Scalable targets =="
aws application-autoscaling describe-scalable-targets --service-namespace ecs \
  --query "ScalableTargets[].{Recurso:ResourceId,Min:MinCapacity,Max:MaxCapacity}" --output table
