#!/bin/bash
# Application Load Balancer publico (2 AZ) + target group + listener para el frontend.
set -euo pipefail
cd "$(dirname "$0")"
source ./00-params.env
source ./ids.env

echo "== ALB =="
ALB_ARN=$(aws elbv2 describe-load-balancers --names "${PROJECT}-alb" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null) || ALB_ARN="None"
if [ "$ALB_ARN" == "None" ] || [ -z "$ALB_ARN" ]; then
  ALB_ARN=$(aws elbv2 create-load-balancer --name "${PROJECT}-alb" --type application --scheme internet-facing \
    --subnets "$SUBNET_PUB_1A" "$SUBNET_PUB_1B" --security-groups "$SG_ALB" \
    --query "LoadBalancers[0].LoadBalancerArn" --output text)
fi
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query "LoadBalancers[0].DNSName" --output text)
echo "ALB_ARN=$ALB_ARN"
echo "ALB_DNS=$ALB_DNS"

echo "== Target group (front) =="
TG_FRONT_ARN=$(aws elbv2 describe-target-groups --names "${PROJECT}-tg-front" --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null) || TG_FRONT_ARN="None"
if [ "$TG_FRONT_ARN" == "None" ] || [ -z "$TG_FRONT_ARN" ]; then
  TG_FRONT_ARN=$(aws elbv2 create-target-group --name "${PROJECT}-tg-front" --protocol HTTP --port 80 \
    --vpc-id "$VPC_ID" --target-type ip \
    --health-check-path "/healthz" --health-check-interval-seconds 30 --healthy-threshold-count 2 \
    --query "TargetGroups[0].TargetGroupArn" --output text)
fi
echo "TG_FRONT_ARN=$TG_FRONT_ARN"

echo "== Listener HTTP:80 =="
LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --query "Listeners[0].ListenerArn" --output text 2>/dev/null) || LISTENER_ARN="None"
if [ "$LISTENER_ARN" == "None" ] || [ -z "$LISTENER_ARN" ]; then
  LISTENER_ARN=$(aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
    --default-actions "Type=forward,TargetGroupArn=$TG_FRONT_ARN" --query "Listeners[0].ListenerArn" --output text)
fi
echo "LISTENER_ARN=$LISTENER_ARN"

echo "== Target group (back) =="
TG_BACK_ARN=$(aws elbv2 describe-target-groups --names "${PROJECT}-tg-back" --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null) || TG_BACK_ARN="None"
if [ "$TG_BACK_ARN" == "None" ] || [ -z "$TG_BACK_ARN" ]; then
  TG_BACK_ARN=$(aws elbv2 create-target-group --name "${PROJECT}-tg-back" --protocol HTTP --port 5000 \
    --vpc-id "$VPC_ID" --target-type ip \
    --health-check-path "/health" --health-check-interval-seconds 30 --healthy-threshold-count 2 \
    --query "TargetGroups[0].TargetGroupArn" --output text)
fi
echo "TG_BACK_ARN=$TG_BACK_ARN"

echo "== Regla de listener: /api/* -> back =="
RULE_EXISTS=$(aws elbv2 describe-rules --listener-arn "$LISTENER_ARN" --query "Rules[?Priority=='10'] | length(@)" --output text)
if [ "$RULE_EXISTS" == "0" ]; then
  aws elbv2 create-rule --listener-arn "$LISTENER_ARN" --priority 10 \
    --conditions "Field=path-pattern,Values='/api/*'" \
    --actions "Type=forward,TargetGroupArn=$TG_BACK_ARN" >/dev/null
  echo "regla creada: /api/* -> $TG_BACK_ARN"
else
  echo "regla ya existia"
fi

grep -v "^export ALB_ARN=\|^export ALB_DNS=\|^export TG_FRONT_ARN=\|^export TG_BACK_ARN=\|^export LISTENER_ARN=" ./ids.env > ./ids.env.tmp || true
mv ./ids.env.tmp ./ids.env
cat >> ./ids.env <<EOF
export ALB_ARN="$ALB_ARN"
export ALB_DNS="$ALB_DNS"
export TG_FRONT_ARN="$TG_FRONT_ARN"
export TG_BACK_ARN="$TG_BACK_ARN"
export LISTENER_ARN="$LISTENER_ARN"
EOF
echo "Listo. URL publica: http://$ALB_DNS/"
