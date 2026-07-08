const test = require("node:test");
const assert = require("node:assert/strict");
const { validarProducto } = require("../server.js");

test("rechaza producto sin nombre", () => {
  const error = validarProducto({ nombre: "", precio: 1000 });
  assert.equal(error, "nombre y precio son obligatorios");
});

test("rechaza producto sin precio", () => {
  const error = validarProducto({ nombre: "Mouse", precio: null });
  assert.equal(error, "nombre y precio son obligatorios");
});

test("rechaza precio negativo", () => {
  const error = validarProducto({ nombre: "Mouse", precio: -10 });
  assert.equal(error, "precio no puede ser negativo");
});

test("acepta producto valido", () => {
  const error = validarProducto({ nombre: "Mouse", precio: 9990 });
  assert.equal(error, null);
});
