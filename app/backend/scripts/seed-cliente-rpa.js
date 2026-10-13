#!/usr/bin/env node
// Crea el cliente sintético del RPA con sus datos de prueba (IP2-76), SIN tocar el esquema.
//
// El robot entra al portal como un cliente real: necesita una cuenta de cliente con el
// correo ya verificado (el despliegue no tiene servicio de correo), una moto y al menos
// un servicio completado para que el recorrido de consulta siempre tenga qué mostrar.
//
//   docker compose run --rm seed
//
// Idempotente: reutiliza lo que ya exista. Sin SEED_CLIENTE_RPA_PASSWORD no crea nada
// (no se dejan credenciales conocidas). Nunca imprime la contraseña.

const bcrypt = require('bcrypt');
const { pool } = require('../src/db/pool');

const EMAIL = process.env.SEED_CLIENTE_RPA_EMAIL || 'cliente.rpa@taller.local';
const PASSWORD = process.env.SEED_CLIENTE_RPA_PASSWORD;
const MOTO = { marca: 'Honda', modelo: 'CB190R', anio: 2022, placa: 'RPA-001', color: 'Rojo', kilometraje: 12500 };

(async () => {
  if (!PASSWORD) {
    console.warn(`⚠️  Cliente sintético (${EMAIL}) omitido: SEED_CLIENTE_RPA_PASSWORD no está definida.`);
    return;
  }
  if (String(PASSWORD).length < 8) {
    console.warn(`⚠️  Cliente sintético (${EMAIL}) omitido: la contraseña debe tener al menos 8 caracteres.`);
    return;
  }

  let [[cliente]] = await pool.query('SELECT id FROM clientes WHERE email = ?', [EMAIL]);
  if (cliente) {
    console.log(`ℹ️  Ya existía el cliente: ${EMAIL}`);
  } else {
    const hash = await bcrypt.hash(String(PASSWORD), 10);
    const [r] = await pool.query(
      `INSERT INTO clientes (nombre, apellido, telefono, email, password_hash, email_verificado, activo)
       VALUES (?, ?, ?, ?, ?, 1, 1)`,
      ['Cliente', 'Sintético RPA', '0000-0000', EMAIL, hash]
    );
    cliente = { id: r.insertId };
    console.log(`✅ Cliente creado: ${EMAIL}`);
  }

  let [[moto]] = await pool.query('SELECT id FROM motos WHERE cliente_id = ? AND placa = ?', [cliente.id, MOTO.placa]);
  if (!moto) {
    const [r] = await pool.query(
      'INSERT INTO motos (cliente_id, marca, modelo, anio, placa, color, kilometraje_actual) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [cliente.id, MOTO.marca, MOTO.modelo, MOTO.anio, MOTO.placa, MOTO.color, MOTO.kilometraje]
    );
    moto = { id: r.insertId };
    console.log(`✅ Moto creada: ${MOTO.marca} ${MOTO.modelo} (${MOTO.placa})`);
  }

  // Un servicio ya entregado: es lo que el portal muestra en el historial de la moto.
  const [[servicio]] = await pool.query(
    "SELECT id FROM citas WHERE cliente_id = ? AND moto_id = ? AND estado = 'entregado' LIMIT 1",
    [cliente.id, moto.id]
  );
  if (!servicio) {
    const [[sucursal]] = await pool.query('SELECT id FROM sucursales WHERE activa = 1 ORDER BY orden, id LIMIT 1');
    await pool.query(
      `INSERT INTO citas (cliente_id, moto_id, sucursal_id, fecha, hora, motivo, tipo_servicio, estado, monto, fecha_inicio, fecha_fin)
       VALUES (?, ?, ?, DATE_SUB(CURDATE(), INTERVAL 30 DAY), '09:00:00', ?, ?, 'entregado', 18000,
               DATE_SUB(NOW(), INTERVAL 30 DAY), DATE_SUB(NOW(), INTERVAL 30 DAY))`,
      [cliente.id, moto.id, sucursal ? sucursal.id : null, 'Servicio de prueba del monitoreo sintético', 'Cambio de aceite']
    );
    console.log('✅ Servicio completado de prueba creado');
  }

  console.log('🎉 Cliente sintético listo.');
})()
  .catch((err) => {
    console.error('❌ Error creando el cliente sintético:', err.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end().catch(() => {}));
