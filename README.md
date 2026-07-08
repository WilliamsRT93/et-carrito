# et-carrito — Innovatech Chile

Carrito de compra/venta/despacho — Evaluación Final Transversal, ISY1101 (Introducción a Herramientas
DevOps). Entorno de orquestación y automatización en la nube sobre **Amazon ECS Fargate**.

## Estructura del repositorio

```
backend/    API REST (Node.js + Express + PostgreSQL) — ver backend/README.md
frontend/   Interfaz web (nginx + JS vanilla) — ver frontend/README.md
db/         Esquema SQL de la base de datos
infra/      Scripts AWS CLI (idempotentes) que crean toda la infraestructura
ecs/        Plantillas de task definition de ECS
```

## Arquitectura

- **VPC dedicada** (`et-vpc`, 10.20.0.0/16) con 2 subredes públicas (us-east-1a/1b) y 1 subred
  privada (us-east-1a).
- **Clúster ECS Fargate** (`et-cluster`) con 2 servicios: `et-svc-front` y `et-svc-back`,
  autoscaling Target Tracking (CPU 50%, min 1 / max 4 tareas cada uno).
- **Application Load Balancer** público (`et-alb`, 2 AZ): enruta `/` al frontend y `/api/*` al
  backend mediante reglas de listener (sin Cloud Map/Service Connect — no disponible en esta
  cuenta AWS Academy).
- **Base de datos PostgreSQL en EC2** (`et-db`), en subred privada, **sin acceso a internet**
  salvo la ventana única de actualización de Linux durante el aprovisionamiento. Administrable
  vía consola del navegador con **AWS Systems Manager Session Manager** (VPC endpoints
  PrivateLink), sin reabrir nunca el acceso a internet.
- **4 Security Groups** encadenados por referencia (principio de mínimo privilegio): `et-alb-sg`
  (80 desde internet) → `et-front-sg` (80 solo desde el ALB) y `et-back-sg` (5000 solo desde el
  ALB, que enruta `/api/*` directo al backend) → `et-db-sg` (5432 solo desde `et-back-sg`).
- **Amazon ECR** con un repositorio por componente (`et-front`, `et-back`).
- **CI/CD con GitHub Actions** (`.github/workflows/deploy.yml`): monorepo con `dorny/paths-filter`
  — cada push corre tests unitarios del backend y solo reconstruye/redespliega el componente que
  cambió.
- **Gestión de secretos**: la contraseña de PostgreSQL no viaja en texto plano. Se guarda en
  **AWS Secrets Manager** (`et-db-password`) y la instancia `et-db` la obtiene en el arranque vía
  `aws secretsmanager get-secret-value`, usando el rol de instancia (`LabInstanceProfile`). Las
  credenciales de AWS y el token de sesión para el pipeline se gestionan como **GitHub Secrets**.

## Desarrollo local con Docker Compose

```bash
cp .env.example .env   # ajustar DB_PASSWORD si se desea
docker compose up -d --build
```

Levanta los 3 servicios (`db`, `backend`, `frontend`) en la red `et-net`, con el volumen nombrado
`et-db-data` para persistir los datos de PostgreSQL entre reinicios. El frontend queda disponible
en `http://localhost:8080`; su nginx hace `proxy_pass` de `/api/` hacia el contenedor `backend`
(en AWS esa ruta la resuelve el ALB, sin pasar por nginx). Ambos Dockerfiles usan imágenes base
`alpine` minimalistas; el del backend es **multietapa** (una etapa instala dependencias con
`npm ci`, la etapa final solo copia `node_modules` y el código, sin herramientas de build).

## Cómo desplegar desde cero

```bash
cd infra
./01-vpc.sh
./02-security-groups.sh
./gen-userdata-db.sh   # genera infra/user-data-db.sh (no se versiona)
./03-db-launch.sh
./04-ssm-endpoints.sh
./05-ecr.sh
./06-ecs-cluster.sh
./07-alb.sh
./08-services.sh
./09-autoscaling.sh
```

Requiere `infra/secrets.env` con `DB_PASSWORD` (no versionado) y credenciales de AWS CLI
configuradas (`aws configure` o variables de entorno).

## Equipo

Williams Rivas · Marcelo Prado
