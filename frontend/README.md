# et-front

Frontend del carrito de compra/venta/despacho de Innovatech Chile (Evaluación Final Transversal,
ISY1101 — Introducción a Herramientas DevOps).

Interfaz estática (HTML + CSS + JavaScript vanilla) servida por **nginx**, ejecutada como tarea
de **Amazon ECS Fargate** detrás de un Application Load Balancer (ALB) con acceso público.

## Arquitectura

- Clúster: `et-cluster` (ECS Fargate).
- Servicio: `et-svc-front`, autoscaling Target Tracking (CPU 50%, min 1 / max 4 tareas).
- Acceso público vía ALB (`et-alb`), puerto 80.
- Las llamadas a la API se hacen a `/api/...` (mismo origen): el ALB enruta ese path
  directamente al backend (`et-svc-back`), por lo que no se requiere CORS ni conocer la IP
  del backend desde el navegador.

## Funcionalidad

- Catálogo de productos con CRUD completo (crear, editar, eliminar).
- Carrito de compra: agregar productos, confirmar venta (genera un despacho automáticamente).
- Listado de despachos con cambio de estado (`pendiente` → `en_ruta` → `entregado`) y eliminación.
- Indicador de estado del backend/BD en el pie de página.

## Ejecutar localmente

```bash
docker build -t et-front .
docker run -p 8080:80 et-front
```

Para probar contra un backend real, usar `docker-compose` o ajustar `default.conf` con la URL
del ALB durante el desarrollo.

## CI/CD

`.github/workflows/deploy.yml` construye la imagen, la publica en Amazon ECR y fuerza un nuevo
despliegue del servicio ECS en cada push a `main`.
