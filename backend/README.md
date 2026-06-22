# ev3-back

Backend del carrito de compra/venta/despacho de Innovatech Chile (Evaluación Parcial N°3,
ISY1101 — Introducción a Herramientas DevOps).

API REST en Node.js + Express + PostgreSQL. Se ejecuta como tarea de **Amazon ECS Fargate**,
detrás de un Application Load Balancer (ALB) que enruta el tráfico `/api/*` hacia este servicio.

## Arquitectura

- Clúster: `ev3-cluster` (ECS Fargate, sin gestión de nodos).
- Servicio: `ev3-svc-back`, autoscaling Target Tracking (CPU 50%, min 1 / max 4 tareas).
- Expuesto internamente vía ALB (`ev3-alb`) con regla de path `/api/*` → target group `ev3-tg-back`.
- Base de datos: PostgreSQL en una instancia EC2 **sin acceso a internet** (subred privada),
  alcanzable solo desde el Security Group del backend (`ev3-back-sg`).

## Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health` | Estado del servicio y conexión a BD |
| GET | `/productos` | Listar catálogo |
| GET | `/productos/:id` | Obtener un producto |
| POST | `/productos` | Crear producto |
| PUT | `/productos/:id` | Actualizar producto |
| DELETE | `/productos/:id` | Eliminar producto |
| GET | `/ventas` | Listar ventas con sus items |
| POST | `/ventas` | Confirmar compra del carrito (descuenta stock, genera despacho) |
| DELETE | `/ventas/:id` | Eliminar venta |
| GET | `/despachos` | Listar despachos |
| PUT | `/despachos/:id` | Cambiar estado (`pendiente` / `en_ruta` / `entregado`) |
| DELETE | `/despachos/:id` | Eliminar despacho |

Todas las rutas existen también bajo el prefijo `/api/...` (montaje doble del mismo router),
porque el ALB enruta `/api/*` directo a este servicio.

## Variables de entorno

| Variable | Descripción |
|---|---|
| `DB_HOST` | IP privada de la instancia EC2 con PostgreSQL |
| `DB_PORT` | Puerto de PostgreSQL (5432) |
| `DB_NAME` | Nombre de la base de datos |
| `DB_USER` | Usuario de la base de datos |
| `DB_PASSWORD` | Contraseña del usuario |
| `PORT` | Puerto donde escucha la API (5000 por defecto) |

## Ejecutar localmente

```bash
npm install
DB_HOST=localhost DB_USER=appuser DB_PASSWORD=*** DB_NAME=innovatech node server.js
```

O con Docker:

```bash
docker build -t ev3-back .
docker run -p 5000:5000 -e DB_HOST=... -e DB_PASSWORD=... ev3-back
```

## CI/CD

`.github/workflows/deploy.yml` (en la raíz del monorepo) usa `dorny/paths-filter` para construir
y desplegar este componente únicamente cuando cambian archivos dentro de `backend/`. Publica la
imagen en Amazon ECR y fuerza un nuevo despliegue del servicio `ev3-svc-back` en ECS.
