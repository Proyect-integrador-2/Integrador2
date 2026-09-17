#!/usr/bin/env node
// Siembra las cuentas iniciales SIN tocar el esquema.
//
// Existe porque `src/db/migrate.js` ejecuta schema.sql, que empieza con DROP TABLE:
// correrlo sobre una base con datos la vacía. En Docker el esquema lo crea MySQL
// una sola vez (docker-entrypoint-initdb.d) y las cuentas se siembran con este script:
//
//   docker compose run --rm seed
//
// Idempotente: INSERT IGNORE por email único. Una cuenta sin contraseña en el
// entorno se omite (no se dejan credenciales conocidas). Nunca imprime contraseñas.

const bcrypt = require('bcrypt');
const { pool } = require('../src/db/pool');

const CUENTAS = [
  { nombre: 'Administrador', rol: 'admin', email: process.env.SEED_ADMIN_EMAIL || 'admin@taller.com', password: process.env.SEED_ADMIN_PASSWORD },
  { nombre: 'Recepción', rol: 'recepcion', email: process.env.SEED_RECEP_EMAIL || 'recepcion@taller.com', password: process.env.SEED_RECEP_PASSWORD },
  // Usuario sintético del RPA: rol de recepción (consulta y registra clientes), cuenta propia
  // para distinguir su actividad en los logs y poder desactivarlo sin afectar a nadie.
  { nombre: 'Usuario sintético RPA', rol: 'recepcion', email: process.env.SEED_RPA_EMAIL || 'rpa@taller.local', password: process.env.SEED_RPA_PASSWORD },
];

(async () => {
  let creadas = 0;
  for (const c of CUENTAS) {
    if (!c.password) {
      console.warn(`⚠️  ${c.rol} (${c.email}) omitido: su contraseña no está definida en el entorno.`);
      continue;
    }
    if (String(c.password).length < 8) {
      console.warn(`⚠️  ${c.rol} (${c.email}) omitido: la contraseña debe tener al menos 8 caracteres.`);
      continue;
    }
    const hash = await bcrypt.hash(String(c.password), 10);
    const [r] = await pool.query(
      'INSERT IGNORE INTO usuarios (nombre, email, password_hash, rol) VALUES (?, ?, ?, ?)',
      [c.nombre, c.email, hash, c.rol]
    );
    if (r.affectedRows) {
      creadas++;
      console.log(`✅ Cuenta creada: ${c.email} (${c.rol})`);
    } else {
      console.log(`ℹ️  Ya existía: ${c.email}`);
    }
  }
  console.log(`🎉 Siembra terminada (${creadas} cuenta(s) nueva(s)).`);
  await pool.end();
})().catch(async (err) => {
  console.error('❌ Error sembrando cuentas:', err.message);
  await pool.end().catch(() => {});
  process.exit(1);
});
