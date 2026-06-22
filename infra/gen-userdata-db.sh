#!/bin/bash
# Genera infra/user-data-db.sh (texto plano) embebiendo db/init.sql.
set -euo pipefail
cd "$(dirname "$0")"
source ./00-params.env
source ./secrets.env

OUT="./user-data-db.sh"

{
  echo "#!/bin/bash"
  echo "exec > /var/log/ev3-userdata.log 2>&1"
  echo "set -x"
  echo ""
  echo "dnf update -y"
  echo "dnf install -y postgresql15-server postgresql15"
  echo "/usr/bin/postgresql-setup --initdb"
  echo "systemctl enable postgresql"
  echo "systemctl start postgresql"
  echo ""
  echo "sed -i \"s/^#listen_addresses.*/listen_addresses = '*'/\" /var/lib/pgsql/data/postgresql.conf"
  echo "echo \"host all all 10.20.0.0/16 scram-sha-256\" >> /var/lib/pgsql/data/pg_hba.conf"
  echo "# El paquete RPM de postgresql en Amazon Linux usa 'ident' por defecto para 127.0.0.1/::1,"
  echo "# lo que bloquea la autenticacion por password incluso en localhost. Se reemplaza por scram-sha-256."
  echo "sed -i 's/ident/scram-sha-256/g' /var/lib/pgsql/data/pg_hba.conf"
  echo "systemctl restart postgresql"
  echo ""
  echo "sudo -u postgres psql -c \"CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';\""
  echo "sudo -u postgres psql -c \"CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};\""
  echo "sudo -u postgres psql -d ${DB_NAME} -c \"ALTER SCHEMA public OWNER TO ${DB_USER};\""
  echo ""
  echo "cat > /tmp/init.sql << 'SQLEOF'"
  cat ../db/init.sql
  echo "SQLEOF"
  echo ""
  echo "PGPASSWORD='${DB_PASSWORD}' psql -h 127.0.0.1 -U ${DB_USER} -d ${DB_NAME} -f /tmp/init.sql"
  echo "rm -f /tmp/init.sql"
  echo "touch /tmp/ev3-userdata-done"
} > "$OUT"

chmod 600 "$OUT"
echo "Generado $OUT ($(wc -l < "$OUT") lineas, contiene credenciales: permisos 600)"
