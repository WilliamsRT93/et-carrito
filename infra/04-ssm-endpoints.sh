#!/bin/bash
# VPC Interface Endpoints (PrivateLink) para SSM Session Manager.
# Permite administrar ev3-db (consola EC2 por navegador) SIN salida a internet,
# manteniendo el aislamiento permanente de la subred privada.
set -euo pipefail
cd "$(dirname "$0")"
source ./00-params.env
source ./ids.env

echo "== Security Group para los endpoints (443 desde la VPC) =="
SG_VPCE=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=${PROJECT}-vpce-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text)
if [ "$SG_VPCE" == "None" ] || [ -z "$SG_VPCE" ]; then
  SG_VPCE=$(aws ec2 create-security-group --group-name "${PROJECT}-vpce-sg" --description "Endpoints SSM - 443 desde la VPC" --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT}-vpce-sg}]" --query "GroupId" --output text)
  aws ec2 authorize-security-group-ingress --group-id "$SG_VPCE" --protocol tcp --port 443 --cidr "$VPC_CIDR" >/dev/null
fi
echo "SG_VPCE=$SG_VPCE"

create_endpoint() {
  local service="$1"
  local existing
  existing=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" "Name=service-name,Values=com.amazonaws.${AWS_REGION}.${service}" \
    --query "VpcEndpoints[0].VpcEndpointId" --output text)
  if [ "$existing" == "None" ] || [ -z "$existing" ]; then
    aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --vpc-endpoint-type Interface \
      --service-name "com.amazonaws.${AWS_REGION}.${service}" \
      --subnet-ids "$SUBNET_PRIV_1A" --security-group-ids "$SG_VPCE" \
      --private-dns-enabled \
      --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${PROJECT}-vpce-${service}}]" \
      --query "VpcEndpoint.VpcEndpointId" --output text
  else
    echo "$existing"
  fi
}

echo "== Creando endpoints ssm / ssmmessages / ec2messages =="
EP_SSM=$(create_endpoint "ssm")
echo "EP_SSM=$EP_SSM"
EP_SSMMSG=$(create_endpoint "ssmmessages")
echo "EP_SSMMSG=$EP_SSMMSG"
EP_EC2MSG=$(create_endpoint "ec2messages")
echo "EP_EC2MSG=$EP_EC2MSG"

grep -v "^export SG_VPCE=" ./ids.env > ./ids.env.tmp || true
mv ./ids.env.tmp ./ids.env
echo "export SG_VPCE=\"$SG_VPCE\"" >> ./ids.env

echo "== Esperando a que los endpoints queden 'available' =="
for ep in "$EP_SSM" "$EP_SSMMSG" "$EP_EC2MSG"; do
  aws ec2 wait vpc-endpoint-exists --vpc-endpoint-ids "$ep" 2>/dev/null || true
done
sleep 20
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "$EP_SSM" "$EP_SSMMSG" "$EP_EC2MSG" \
  --query "VpcEndpoints[].{Servicio:ServiceName,Estado:State}" --output table
