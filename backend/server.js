const express = require("express");
const cors = require("cors");
const { Pool } = require("pg");

const app = express();
app.use(cors());
app.use(express.json());

// El ALB enruta "/api/*" directo al backend (sin Cloud Map / Service Connect,
// no disponible en esta cuenta AWS Academy); se monta el mismo router en "/"
// (pruebas directas) y en "/api" (a través del ALB) para no duplicar rutas.
const router = express.Router();

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || "innovatech",
  user: process.env.DB_USER || "appuser",
  password: process.env.DB_PASSWORD,
  max: 5,
  idleTimeoutMillis: 30000,
});

const PORT = process.env.PORT || 5000;

// Envuelve cada ruta async: evita que un error de BD sin capturar tumbe el proceso
// (Node mata el proceso ante una promesa rechazada no manejada).
function asyncRoute(handler) {
  return async (req, res) => {
    try {
      await handler(req, res);
    } catch (err) {
      if (err.code === "23503") {
        return res.status(409).json({
          error: "No se puede eliminar: el registro está referenciado por otro recurso (por ejemplo, una venta ya realizada).",
        });
      }
      console.error(err);
      res.status(500).json({ error: "Error interno del servidor" });
    }
  };
}

router.get("/health", asyncRoute(async (_req, res) => {
  await pool.query("SELECT 1");
  res.json({ status: "ok", db: true });
}));

// Endpoint temporal para la prueba de carga del autoscaling (IE3): genera trabajo
// real de CPU (hashing) para poder demostrar el Target Tracking sin depender del
// throughput de red del cliente de pruebas. Se retira despues de la demostracion.
// El trabajo se hace en lotes con setImmediate para CEDER el event loop entre
// lotes: si se hace todo de forma sincrona, /health queda bloqueado detras del
// computo y el ALB marca la tarea "unhealthy" (la reemplaza) en vez de escalarla.
const crypto = require("crypto");
function yieldLoop() {
  return new Promise((resolve) => setImmediate(resolve));
}
router.get("/stress", async (_req, res) => {
  let data = "ev3-carga-" + Date.now();
  for (let batch = 0; batch < 200; batch++) {
    for (let i = 0; i < 1000; i++) {
      data = crypto.createHash("sha256").update(data).digest("hex");
    }
    await yieldLoop();
  }
  res.json({ ok: true, hash: data.slice(0, 16) });
});

// ---------- Productos (CRUD completo) ----------

router.get("/productos", asyncRoute(async (_req, res) => {
  const { rows } = await pool.query("SELECT * FROM productos ORDER BY id");
  res.json(rows);
}));

router.get("/productos/:id", asyncRoute(async (req, res) => {
  const { rows } = await pool.query("SELECT * FROM productos WHERE id = $1", [req.params.id]);
  if (!rows.length) return res.status(404).json({ error: "Producto no encontrado" });
  res.json(rows[0]);
}));

router.post("/productos", asyncRoute(async (req, res) => {
  const { nombre, descripcion, precio, stock } = req.body;
  if (!nombre || precio == null) {
    return res.status(400).json({ error: "nombre y precio son obligatorios" });
  }
  const { rows } = await pool.query(
    "INSERT INTO productos (nombre, descripcion, precio, stock) VALUES ($1, $2, $3, $4) RETURNING *",
    [nombre, descripcion || null, precio, stock || 0]
  );
  res.status(201).json(rows[0]);
}));

router.put("/productos/:id", asyncRoute(async (req, res) => {
  const { nombre, descripcion, precio, stock } = req.body;
  const { rows } = await pool.query(
    `UPDATE productos SET nombre = COALESCE($1, nombre), descripcion = COALESCE($2, descripcion),
       precio = COALESCE($3, precio), stock = COALESCE($4, stock) WHERE id = $5 RETURNING *`,
    [nombre, descripcion, precio, stock, req.params.id]
  );
  if (!rows.length) return res.status(404).json({ error: "Producto no encontrado" });
  res.json(rows[0]);
}));

router.delete("/productos/:id", asyncRoute(async (req, res) => {
  const { rowCount } = await pool.query("DELETE FROM productos WHERE id = $1", [req.params.id]);
  if (!rowCount) return res.status(404).json({ error: "Producto no encontrado" });
  res.status(204).send();
}));

// ---------- Ventas (compra del carrito) ----------

router.get("/ventas", asyncRoute(async (_req, res) => {
  const { rows } = await pool.query(`
    SELECT v.*, COALESCE(json_agg(json_build_object(
        'producto_id', vi.producto_id, 'cantidad', vi.cantidad, 'precio_unitario', vi.precio_unitario
      )) FILTER (WHERE vi.id IS NOT NULL), '[]') AS items
    FROM ventas v
    LEFT JOIN venta_items vi ON vi.venta_id = v.id
    GROUP BY v.id ORDER BY v.id DESC
  `);
  res.json(rows);
}));

router.post("/ventas", asyncRoute(async (req, res) => {
  const { cliente, direccion, items } = req.body;
  if (!cliente || !direccion || !Array.isArray(items) || !items.length) {
    return res.status(400).json({ error: "cliente, direccion e items son obligatorios" });
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    let total = 0;
    for (const item of items) {
      const { rows } = await client.query("SELECT precio, stock FROM productos WHERE id = $1 FOR UPDATE", [item.producto_id]);
      if (!rows.length) throw new Error(`Producto ${item.producto_id} no existe`);
      if (rows[0].stock < item.cantidad) throw new Error(`Stock insuficiente para producto ${item.producto_id}`);
      total += Number(rows[0].precio) * item.cantidad;
    }

    const ventaRes = await client.query(
      "INSERT INTO ventas (cliente, total) VALUES ($1, $2) RETURNING *",
      [cliente, total]
    );
    const venta = ventaRes.rows[0];

    for (const item of items) {
      const { rows } = await client.query("SELECT precio FROM productos WHERE id = $1", [item.producto_id]);
      await client.query(
        "INSERT INTO venta_items (venta_id, producto_id, cantidad, precio_unitario) VALUES ($1, $2, $3, $4)",
        [venta.id, item.producto_id, item.cantidad, rows[0].precio]
      );
      await client.query("UPDATE productos SET stock = stock - $1 WHERE id = $2", [item.cantidad, item.producto_id]);
    }

    const despachoRes = await client.query(
      "INSERT INTO despachos (venta_id, direccion, estado) VALUES ($1, $2, 'pendiente') RETURNING *",
      [venta.id, direccion]
    );

    await client.query("COMMIT");
    res.status(201).json({ venta, despacho: despachoRes.rows[0] });
  } catch (err) {
    await client.query("ROLLBACK");
    res.status(400).json({ error: err.message });
  } finally {
    client.release();
  }
}));

router.delete("/ventas/:id", asyncRoute(async (req, res) => {
  const { rowCount } = await pool.query("DELETE FROM ventas WHERE id = $1", [req.params.id]);
  if (!rowCount) return res.status(404).json({ error: "Venta no encontrada" });
  res.status(204).send();
}));

// ---------- Despachos (CRUD completo) ----------

router.get("/despachos", asyncRoute(async (_req, res) => {
  const { rows } = await pool.query(`
    SELECT d.*, v.cliente, v.total FROM despachos d
    JOIN ventas v ON v.id = d.venta_id ORDER BY d.id DESC
  `);
  res.json(rows);
}));

router.put("/despachos/:id", asyncRoute(async (req, res) => {
  const { estado, direccion } = req.body;
  const validos = ["pendiente", "en_ruta", "entregado"];
  if (estado && !validos.includes(estado)) {
    return res.status(400).json({ error: `estado debe ser uno de: ${validos.join(", ")}` });
  }
  const { rows } = await pool.query(
    `UPDATE despachos SET estado = COALESCE($1, estado), direccion = COALESCE($2, direccion),
       actualizado = now() WHERE id = $3 RETURNING *`,
    [estado, direccion, req.params.id]
  );
  if (!rows.length) return res.status(404).json({ error: "Despacho no encontrado" });
  res.json(rows[0]);
}));

router.delete("/despachos/:id", asyncRoute(async (req, res) => {
  const { rowCount } = await pool.query("DELETE FROM despachos WHERE id = $1", [req.params.id]);
  if (!rowCount) return res.status(404).json({ error: "Despacho no encontrado" });
  res.status(204).send();
}));

app.use("/", router);
app.use("/api", router);

app.listen(PORT, () => console.log(`ev3-back escuchando en puerto ${PORT}`));
