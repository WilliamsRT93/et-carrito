// El frontend llama siempre a /api/... ; nginx hace proxy_pass hacia el backend
// interno del clúster (DNS de ECS Service Connect), por eso no hace falta CORS
// ni conocer la IP del backend desde el navegador.
const API_BASE = "/api";

let carrito = [];
let productosCache = [];
let editandoId = null;

async function cargarProductos() {
  const res = await fetch(`${API_BASE}/productos`);
  productosCache = await res.json();
  renderProductos();
}

function renderProductos() {
  const tbody = document.querySelector("#tabla-productos tbody");
  tbody.innerHTML = "";
  for (const p of productosCache) {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${p.id}</td>
      <td>${p.nombre}</td>
      <td>${p.descripcion || ""}</td>
      <td>$${Number(p.precio).toLocaleString("es-CL")}</td>
      <td>${p.stock}</td>
      <td>
        <button data-action="agregar-carrito" data-id="${p.id}">Agregar al carrito</button>
        <button data-action="editar" data-id="${p.id}" class="secundario">Editar</button>
        <button data-action="eliminar" data-id="${p.id}" class="peligro">Eliminar</button>
      </td>`;
    tbody.appendChild(tr);
  }
}

document.querySelector("#tabla-productos").addEventListener("click", async (e) => {
  const btn = e.target.closest("button");
  if (!btn) return;
  const id = btn.dataset.id;
  const accion = btn.dataset.action;

  if (accion === "agregar-carrito") {
    const producto = productosCache.find((p) => String(p.id) === id);
    agregarAlCarrito(producto);
  } else if (accion === "editar") {
    const producto = productosCache.find((p) => String(p.id) === id);
    cargarProductoEnFormulario(producto);
  } else if (accion === "eliminar") {
    if (!confirm(`¿Eliminar producto #${id}?`)) return;
    await fetch(`${API_BASE}/productos/${id}`, { method: "DELETE" });
    await cargarProductos();
  }
});

function cargarProductoEnFormulario(p) {
  editandoId = p.id;
  document.querySelector("#producto-id").value = p.id;
  document.querySelector("#producto-nombre").value = p.nombre;
  document.querySelector("#producto-descripcion").value = p.descripcion || "";
  document.querySelector("#producto-precio").value = p.precio;
  document.querySelector("#producto-stock").value = p.stock;
  document.querySelector("#btn-guardar-producto").textContent = "Guardar cambios";
  document.querySelector("#btn-cancelar-edicion").hidden = false;
}

function limpiarFormularioProducto() {
  editandoId = null;
  document.querySelector("#form-producto").reset();
  document.querySelector("#btn-guardar-producto").textContent = "Agregar producto";
  document.querySelector("#btn-cancelar-edicion").hidden = true;
}

document.querySelector("#btn-cancelar-edicion").addEventListener("click", limpiarFormularioProducto);

document.querySelector("#form-producto").addEventListener("submit", async (e) => {
  e.preventDefault();
  const body = {
    nombre: document.querySelector("#producto-nombre").value,
    descripcion: document.querySelector("#producto-descripcion").value,
    precio: Number(document.querySelector("#producto-precio").value),
    stock: Number(document.querySelector("#producto-stock").value),
  };

  if (editandoId) {
    await fetch(`${API_BASE}/productos/${editandoId}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } else {
    await fetch(`${API_BASE}/productos`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  }
  limpiarFormularioProducto();
  await cargarProductos();
});

function agregarAlCarrito(producto) {
  const existente = carrito.find((i) => i.producto_id === producto.id);
  if (existente) {
    existente.cantidad += 1;
  } else {
    carrito.push({ producto_id: producto.id, nombre: producto.nombre, precio: producto.precio, cantidad: 1 });
  }
  renderCarrito();
}

function renderCarrito() {
  const cont = document.querySelector("#items-carrito");
  cont.innerHTML = "";
  let total = 0;
  for (const item of carrito) {
    total += item.precio * item.cantidad;
    const div = document.createElement("div");
    div.textContent = `${item.nombre} x${item.cantidad} — $${(item.precio * item.cantidad).toLocaleString("es-CL")}`;
    cont.appendChild(div);
  }
  document.querySelector("#carrito-total").textContent = total.toLocaleString("es-CL");
}

document.querySelector("#form-venta").addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!carrito.length) {
    alert("El carrito está vacío");
    return;
  }
  const body = {
    cliente: document.querySelector("#venta-cliente").value,
    direccion: document.querySelector("#venta-direccion").value,
    items: carrito.map((i) => ({ producto_id: i.producto_id, cantidad: i.cantidad })),
  };
  const res = await fetch(`${API_BASE}/ventas`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const err = await res.json();
    alert(`Error al confirmar la venta: ${err.error}`);
    return;
  }
  carrito = [];
  renderCarrito();
  document.querySelector("#form-venta").reset();
  await cargarProductos();
  await cargarDespachos();
});

async function cargarDespachos() {
  const res = await fetch(`${API_BASE}/despachos`);
  const despachos = await res.json();
  const tbody = document.querySelector("#tabla-despachos tbody");
  tbody.innerHTML = "";
  for (const d of despachos) {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${d.id}</td>
      <td>${d.cliente}</td>
      <td>${d.direccion}</td>
      <td>$${Number(d.total).toLocaleString("es-CL")}</td>
      <td><span class="badge ${d.estado}">${d.estado}</span></td>
      <td>
        <select data-id="${d.id}" class="select-estado">
          <option value="pendiente" ${d.estado === "pendiente" ? "selected" : ""}>pendiente</option>
          <option value="en_ruta" ${d.estado === "en_ruta" ? "selected" : ""}>en_ruta</option>
          <option value="entregado" ${d.estado === "entregado" ? "selected" : ""}>entregado</option>
        </select>
        <button data-action="eliminar-despacho" data-id="${d.id}" class="peligro">Eliminar</button>
      </td>`;
    tbody.appendChild(tr);
  }
}

document.querySelector("#tabla-despachos").addEventListener("change", async (e) => {
  if (!e.target.matches(".select-estado")) return;
  const id = e.target.dataset.id;
  await fetch(`${API_BASE}/despachos/${id}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ estado: e.target.value }),
  });
  await cargarDespachos();
});

document.querySelector("#tabla-despachos").addEventListener("click", async (e) => {
  const btn = e.target.closest("button[data-action='eliminar-despacho']");
  if (!btn) return;
  if (!confirm(`¿Eliminar despacho #${btn.dataset.id}?`)) return;
  await fetch(`${API_BASE}/despachos/${btn.dataset.id}`, { method: "DELETE" });
  await cargarDespachos();
});

async function verificarBackend() {
  const el = document.querySelector("#estado-backend");
  try {
    const res = await fetch(`${API_BASE}/health`);
    const data = await res.json();
    el.textContent = `Backend: ${data.status} (BD: ${data.db ? "conectada" : "sin conexión"})`;
  } catch {
    el.textContent = "Backend: sin respuesta";
  }
}

cargarProductos();
cargarDespachos();
verificarBackend();
setInterval(verificarBackend, 15000);
