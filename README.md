# ev3-carrito — Innovatech Chile

Carrito de compra/venta/despacho — Evaluación Parcial N°3, ISY1101 (Introducción a Herramientas
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

- **VPC dedicada** (`ev3-vpc`, 10.20.0.0/16) con 2 subredes públicas (us-east-1a/1b) y 1 subred
  privada (us-east-1a).
- **Clúster ECS Fargate** (`ev3-cluster`) con 2 servicios: `ev3-svc-front` y `ev3-svc-back`,
  autoscaling Target Tracking (CPU 50%, min 1 / max 4 tareas cada uno).
- **Application Load Balancer** público (`ev3-alb`, 2 AZ): enruta `/` al frontend y `/api/*` al
  backend mediante reglas de listener (sin Cloud Map/Service Connect — no disponible en esta
  cuenta AWS Academy).
- **Base de datos PostgreSQL en EC2** (`ev3-db`), en subred privada, **sin acceso a internet**
  salvo la ventana única de actualización de Linux durante el aprovisionamiento. Administrable
  vía consola del navegador con **AWS Systems Manager Session Manager** (VPC endpoints
  PrivateLink), sin reabrir nunca el acceso a internet.
- **4 Security Groups** encadenados por referencia: `ev3-alb-sg` → `ev3-front-sg` / `ev3-back-sg`
  → `ev3-db-sg` (principio de mínimo privilegio).
- **Amazon ECR** con un repositorio por componente (`ev3-front`, `ev3-back`).
- **CI/CD con GitHub Actions** (`.github/workflows/deploy.yml`): monorepo con `dorny/paths-filter`
  — cada push solo reconstruye y redespliega el componente que cambió.

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
