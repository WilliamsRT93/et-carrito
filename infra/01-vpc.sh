#!/bin/bash
# Crea la VPC, subredes (2 públicas en 2 AZ + 1 privada), IGW y route tables del proyecto EP3.
# Idempotente: si el recurso ya existe (por tag Name), lo reutiliza.
set -euo pipefail
cd "$(dirname "$0")"
source ./00-params.env

IDS_FILE="./ids.env"
touch "$IDS_FILE"
source "$IDS_FILE"

tag_filter() { echo "Name=tag:Name,Values=$1"; }

echo "== 1. VPC =="
VPC_ID=$(aws ec2 describe-vpcs --filters $(tag_filter "${PROJECT}-vpc") --query "Vpcs[0].VpcId" --output text)
if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
  VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT}-vpc}]" \
    --query "Vpc.VpcId" --output text)
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
fi
echo "VPC_ID=$VPC_ID"

echo "== 2. Subredes =="
SUBNET_PUB_1A=$(aws ec2 describe-subnets --filters $(tag_filter "${PROJECT}-pub-1a") --query "Subnets[0].SubnetId" --output text)
if [ "$SUBNET_PUB_1A" == "None" ] || [ -z "$SUBNET_PUB_1A" ]; then
  SUBNET_PUB_1A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_PUB_1A_CIDR" --availability-zone "$AZ_A" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-pub-1a}]" --query "Subnet.SubnetId" --output text)
  aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_PUB_1A" --map-public-ip-on-launch
fi
echo "SUBNET_PUB_1A=$SUBNET_PUB_1A"

SUBNET_PUB_1B=$(aws ec2 describe-subnets --filters $(tag_filter "${PROJECT}-pub-1b") --query "Subnets[0].SubnetId" --output text)
if [ "$SUBNET_PUB_1B" == "None" ] || [ -z "$SUBNET_PUB_1B" ]; then
  SUBNET_PUB_1B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_PUB_1B_CIDR" --availability-zone "$AZ_B" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-pub-1b}]" --query "Subnet.SubnetId" --output text)
  aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_PUB_1B" --map-public-ip-on-launch
fi
echo "SUBNET_PUB_1B=$SUBNET_PUB_1B"

SUBNET_PRIV_1A=$(aws ec2 describe-subnets --filters $(tag_filter "${PROJECT}-priv-1a") --query "Subnets[0].SubnetId" --output text)
if [ "$SUBNET_PRIV_1A" == "None" ] || [ -z "$SUBNET_PRIV_1A" ]; then
  SUBNET_PRIV_1A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_PRIV_1A_CIDR" --availability-zone "$AZ_A" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-priv-1a}]" --query "Subnet.SubnetId" --output text)
fi
echo "SUBNET_PRIV_1A=$SUBNET_PRIV_1A"

echo "== 3. Internet Gateway =="
IGW_ID=$(aws ec2 describe-internet-gateways --filters $(tag_filter "${PROJECT}-igw") --query "InternetGateways[0].InternetGatewayId" --output text)
if [ "$IGW_ID" == "None" ] || [ -z "$IGW_ID" ]; then
  IGW_ID=$(aws ec2 create-internet-gateway --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT}-igw}]" \
    --query "InternetGateway.InternetGatewayId" --output text)
  aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
fi
echo "IGW_ID=$IGW_ID"

echo "== 4. Route table pública =="
RT_PUB_ID=$(aws ec2 describe-route-tables --filters $(tag_filter "${PROJECT}-rt-public") --query "RouteTables[0].RouteTableId" --output text)
if [ "$RT_PUB_ID" == "None" ] || [ -z "$RT_PUB_ID" ]; then
  RT_PUB_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT}-rt-public}]" --query "RouteTable.RouteTableId" --output text)
  aws ec2 create-route --route-table-id "$RT_PUB_ID" --destination-cidr-block "0.0.0.0/0" --gateway-id "$IGW_ID" >/dev/null
  aws ec2 associate-route-table --route-table-id "$RT_PUB_ID" --subnet-id "$SUBNET_PUB_1A" >/dev/null
  aws ec2 associate-route-table --route-table-id "$RT_PUB_ID" --subnet-id "$SUBNET_PUB_1B" >/dev/null
fi
echo "RT_PUB_ID=$RT_PUB_ID"

echo "== 5. Route table privada (sin ruta a internet) =="
RT_PRIV_ID=$(aws ec2 describe-route-tables --filters $(tag_filter "${PROJECT}-rt-private") --query "RouteTables[0].RouteTableId" --output text)
if [ "$RT_PRIV_ID" == "None" ] || [ -z "$RT_PRIV_ID" ]; then
  RT_PRIV_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT}-rt-private}]" --query "RouteTable.RouteTableId" --output text)
  aws ec2 associate-route-table --route-table-id "$RT_PRIV_ID" --subnet-id "$SUBNET_PRIV_1A" >/dev/null
fi
echo "RT_PRIV_ID=$RT_PRIV_ID (sin ruta 0.0.0.0/0 -> BD aislada)"

cat > "$IDS_FILE" <<EOF
export VPC_ID="$VPC_ID"
export SUBNET_PUB_1A="$SUBNET_PUB_1A"
export SUBNET_PUB_1B="$SUBNET_PUB_1B"
export SUBNET_PRIV_1A="$SUBNET_PRIV_1A"
export IGW_ID="$IGW_ID"
export RT_PUB_ID="$RT_PUB_ID"
export RT_PRIV_ID="$RT_PRIV_ID"
EOF
echo "== IDs guardados en $IDS_FILE =="
cat "$IDS_FILE"
