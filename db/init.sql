-- Esquema del carrito de compra/venta/despacho (Innovatech Chile)

CREATE TABLE IF NOT EXISTS productos (
  id SERIAL PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  descripcion TEXT,
  precio NUMERIC(10,2) NOT NULL,
  stock INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS ventas (
  id SERIAL PRIMARY KEY,
  cliente VARCHAR(100) NOT NULL,
  total NUMERIC(10,2) NOT NULL,
  fecha TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS venta_items (
  id SERIAL PRIMARY KEY,
  venta_id INTEGER NOT NULL REFERENCES ventas(id) ON DELETE CASCADE,
  producto_id INTEGER NOT NULL REFERENCES productos(id),
  cantidad INTEGER NOT NULL,
  precio_unitario NUMERIC(10,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS despachos (
  id SERIAL PRIMARY KEY,
  venta_id INTEGER NOT NULL REFERENCES ventas(id) ON DELETE CASCADE,
  direccion VARCHAR(200) NOT NULL,
  estado VARCHAR(20) NOT NULL DEFAULT 'pendiente',
  actualizado TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO productos (nombre, descripcion, precio, stock) VALUES
  ('Mouse inalámbrico', 'Mouse óptico inalámbrico 2.4GHz', 9990, 50),
  ('Teclado mecánico', 'Teclado mecánico switches rojos', 29990, 30),
  ('Monitor 24 pulgadas', 'Monitor LED Full HD 24 pulgadas', 119990, 15),
  ('Audífonos Bluetooth', 'Audífonos over-ear con cancelación de ruido', 24990, 40),
  ('Webcam HD', 'Webcam 1080p con micrófono integrado', 17990, 25)
ON CONFLICT DO NOTHING;
