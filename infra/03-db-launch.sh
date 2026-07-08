#!/bin/bash
# Lanza et-db en la subred privada. Abre una ventana de internet UNA SOLA VEZ
# (EIP temporal + ruta temporal a IGW) para que el user-data actualice Linux
# e instale PostgreSQL. Al terminar, cierra la ventana de forma permanente.
set -euo pipefail
cd "$(dirname "$0")"
source ./00-params.env
source ./ids.env

AMI_ID=$(aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text)
echo "AMI_ID=$AMI_ID"

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${PROJECT}-db" "Name=instance-state-name,Values=pending,running,stopped" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
  echo "== 1. Lanzando instancia ${PROJECT}-db en subred privada =="
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type t3.micro \
    --subnet-id "$SUBNET_PRIV_1A" \
    --security-group-ids "$SG_DB" \
    --iam-instance-profile Name=LabInstanceProfile \
    --user-data file://user-data-db.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}-db}]" \
    --query "Instances[0].InstanceId" --output text)
  echo "INSTANCE_ID=$INSTANCE_ID"
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
else
  echo "Instancia ya existe: $INSTANCE_ID"
fi

DB_PRIVATE_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
echo "DB_PRIVATE_IP=$DB_PRIVATE_IP"

echo "== 2. Ventana temporal de internet (EIP + ruta a IGW) =="
EIP_ALLOC=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=${PROJECT}-db-temp-eip" \
  --query "Addresses[0].AllocationId" --output text)
if [ "$EIP_ALLOC" == "None" ] || [ -z "$EIP_ALLOC" ]; then
  EIP_ALLOC=$(aws ec2 allocate-address --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${PROJECT}-db-temp-eip}]" \
    --query "AllocationId" --output text)
fi
echo "EIP_ALLOC=$EIP_ALLOC"

ASSOC_ID=$(aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$EIP_ALLOC" --query "AssociationId" --output text)
echo "ASSOC_ID=$ASSOC_ID"

ROUTE_EXISTS=$(aws ec2 describe-route-tables --route-table-ids "$RT_PRIV_ID" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'] | length(@)" --output text)
if [ "$ROUTE_EXISTS" == "0" ]; then
  aws ec2 create-route --route-table-id "$RT_PRIV_ID" --destination-cidr-block "0.0.0.0/0" --gateway-id "$IGW_ID" >/dev/null
  echo "Ruta temporal 0.0.0.0/0 -> IGW agregada a $RT_PRIV_ID"
else
  echo "Ruta a internet ya estaba presente en $RT_PRIV_ID"
fi

echo "== 3. Esperando que el user-data termine (update Linux + PostgreSQL + esquema) =="
DONE=""
for i in $(seq 1 20); do
  sleep 15
  CMD_ID=$(aws ssm send-command --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["test -f /tmp/ev3-userdata-done && echo DONE || echo PENDING"]' \
    --query "Command.CommandId" --output text 2>/dev/null) || { echo "intento $i: SSM aun no listo"; continue; }
  sleep 3
  STATUS=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query "StandardOutputContent" --output text 2>/dev/null || echo "PENDING")
  echo "intento $i: $STATUS"
  if [[ "$STATUS" == *DONE* ]]; then DONE="yes"; break; fi
done

if [ -z "$DONE" ]; then
  echo "ADVERTENCIA: no se confirmo el fin del user-data en el tiempo esperado. Revisar /var/log/ev3-userdata.log via SSM antes de cerrar la ventana."
fi

echo "== 4. Cerrando la ventana de internet de forma PERMANENTE =="
aws ec2 disassociate-address --association-id "$ASSOC_ID"
aws ec2 release-address --allocation-id "$EIP_ALLOC"
aws ec2 delete-route --route-table-id "$RT_PRIV_ID" --destination-cidr-block "0.0.0.0/0"
echo "BD aislada: sin IP publica y sin ruta a internet en $RT_PRIV_ID"

grep -v "^export INSTANCE_ID_DB=\|^export DB_PRIVATE_IP=" ./ids.env > ./ids.env.tmp || true
mv ./ids.env.tmp ./ids.env
cat >> ./ids.env <<EOF
export INSTANCE_ID_DB="$INSTANCE_ID"
export DB_PRIVATE_IP="$DB_PRIVATE_IP"
EOF
echo "Listo. INSTANCE_ID_DB=$INSTANCE_ID DB_PRIVATE_IP=$DB_PRIVATE_IP"
