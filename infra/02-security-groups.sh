#!/bin/bash
# Crea los 4 Security Groups (GC) encadenados por referencia: alb -> front -> back -> db
set -euo pipefail
cd "$(dirname "$0")"
source ./00-params.env
source ./ids.env

get_or_create_sg() {
  local name="$1" desc="$2"
  local id
  id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=$name" "Name=vpc-id,Values=$VPC_ID" \
        --query "SecurityGroups[0].GroupId" --output text)
  if [ "$id" == "None" ] || [ -z "$id" ]; then
    id=$(aws ec2 create-security-group --group-name "$name" --description "$desc" --vpc-id "$VPC_ID" \
          --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$name}]" --query "GroupId" --output text)
  fi
  echo "$id"
}

echo "== Security Groups (GC) =="
SG_ALB=$(get_or_create_sg "${PROJECT}-alb-sg" "ALB publico - 80 desde internet")
echo "SG_ALB=$SG_ALB"
SG_FRONT=$(get_or_create_sg "${PROJECT}-front-sg" "Tareas Fargate frontend")
echo "SG_FRONT=$SG_FRONT"
SG_BACK=$(get_or_create_sg "${PROJECT}-back-sg" "Tareas Fargate backend")
echo "SG_BACK=$SG_BACK"
SG_DB=$(get_or_create_sg "${PROJECT}-db-sg" "EC2 base de datos aislada")
echo "SG_DB=$SG_DB"

add_rule() {
  local sg="$1" port="$2" src="$3" desc="$4"
  aws ec2 authorize-security-group-ingress --group-id "$sg" --protocol tcp --port "$port" \
    --source-group "$src" 2>/dev/null \
    && echo "  + regla: $sg <- puerto $port desde $src ($desc)" \
    || echo "  = ya existia: $sg <- puerto $port desde $src"
}

echo "== Reglas de ingreso =="
aws ec2 authorize-security-group-ingress --group-id "$SG_ALB" --protocol tcp --port 80 --cidr "0.0.0.0/0" 2>/dev/null \
  && echo "  + regla: $SG_ALB <- 80 desde 0.0.0.0/0" || echo "  = ya existia: $SG_ALB <- 80 desde 0.0.0.0/0"

add_rule "$SG_FRONT" 80 "$SG_ALB" "ALB -> Front"
add_rule "$SG_BACK" 5000 "$SG_FRONT" "Front -> Back"
add_rule "$SG_DB" 5432 "$SG_BACK" "Back -> BD"

grep -v "^export SG_" ./ids.env > ./ids.env.tmp || true
mv ./ids.env.tmp ./ids.env
cat >> ./ids.env <<EOF
export SG_ALB="$SG_ALB"
export SG_FRONT="$SG_FRONT"
export SG_BACK="$SG_BACK"
export SG_DB="$SG_DB"
EOF
echo "== IDs de SG agregados a ids.env =="
