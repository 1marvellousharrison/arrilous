import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { AsyncLocalStorage } from 'node:async_hooks';
import pg from 'pg';
import { config } from '../config.js';

// node-postgres hands back int8 (COUNT/SUM) and numeric as strings, while the
// in-process PGlite engine and the old SQLite driver returned numbers. Parsing
// them here keeps every caller — and every JSON response — seeing a number.
pg.types.setTypeParser(20, (value) => (value === null ? null : Number(value)));
pg.types.setTypeParser(1700, (value) => (value === null ? null : Number(value)));

const MIGRATIONS_DIR = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  'migrations'
);

// Postgres equivalent of SQLite's strftime('%Y-%m-%dT%H:%M:%fZ', 'now'): an ISO
// UTC timestamp with millisecond precision, so stored text matches
// `new Date().toISOString()` exactly.
const NOW_ISO = `to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`;

// When a transaction is open, its dedicated connection is the executor for
// every helper call made inside it, so `run`/`queryOne`/`queryAll` transparently
// join the transaction rather than grabbing a different pooled connection.
const als = new AsyncLocalStorage();

let driver; // 'pg' | 'pglite'
let db; // executor with .query(sql, params)
let pool; // pg.Pool, when driver === 'pg'
let pglite; // PGlite instance, when driver === 'pglite'

function poolConfig(connectionString) {
  const isLocal = /(^|@|\/\/)(localhost|127\.0\.0\.1)/.test(connectionString);
  return {
    connectionString,
    // Supabase (and most managed Postgres) present a certificate the local
    // trust store does not know, so verification is relaxed for remote hosts.
    ssl: isLocal ? false : { rejectUnauthorized: false },
    max: Number.parseInt(process.env.PG_POOL_MAX ?? '5', 10),
  };
}

/**
 * Opens (and memoises) the connection. A DATABASE_URL selects real Postgres;
 * otherwise an in-process PGlite instance stands in — in-memory unless
 * PGLITE_DATA_DIR is set.
 */
export async function getDb() {
  if (db) return db;

  if (config.databaseUrl) {
    driver = 'pg';
    pool = new pg.Pool(poolConfig(config.databaseUrl));
    db = pool;
    return db;
  }

  driver = 'pglite';
  const { PGlite } = await import('@electric-sql/pglite');
  pglite = config.pgliteDataDir ? new PGlite(config.pgliteDataDir) : new PGlite();
  await pglite.waitReady;
  db = pglite;
  return db;
}

export async function closeDb() {
  if (pool) {
    await pool.end();
    pool = undefined;
  }
  if (pglite) {
    await pglite.close();
    pglite = undefined;
  }
  db = undefined;
}

function executor() {
  return als.getStore() ?? db;
}

/**
 * Rewrites SQLite-style `?` placeholders into Postgres `$1, $2, ...`. The query
 * text in this codebase never contains a literal `?` inside a string, so a
 * linear scan is safe.
 */
function toPlaceholders(sql) {
  let index = 0;
  return sql.replace(/\?/g, () => `$${++index}`);
}

function normalise(value) {
  return value === undefined ? null : value;
}

export async function queryOne(sql, ...params) {
  await getDb();
  const result = await executor().query(
    toPlaceholders(sql),
    params.map(normalise)
  );
  return result.rows[0] ? { ...result.rows[0] } : undefined;
}

export async function queryAll(sql, ...params) {
  await getDb();
  const result = await executor().query(
    toPlaceholders(sql),
    params.map(normalise)
  );
  return result.rows.map((row) => ({ ...row }));
}

export async function run(sql, ...params) {
  await getDb();
  const result = await executor().query(
    toPlaceholders(sql),
    params.map(normalise)
  );
  const changes = result.rowCount ?? result.affectedRows ?? 0;
  return { changes };
}

/** Runs one or more statements with no parameters (used by the migrator). */
async function exec(sql) {
  await getDb();
  const ex = executor();
  return driver === 'pg' ? ex.query(sql) : ex.exec(sql);
}

/**
 * Runs `fn` inside a database transaction. Nested calls join the transaction
 * already open on this async context instead of opening a second one.
 */
export async function transaction(fn) {
  await getDb();
  if (als.getStore()) return fn();

  if (driver === 'pg') {
    const conn = await pool.connect();
    try {
      await conn.query('BEGIN');
      const result = await als.run(conn, () => fn());
      await conn.query('COMMIT');
      return result;
    } catch (error) {
      try {
        await conn.query('ROLLBACK');
      } catch {
        // The connection is already unusable; the original error is the one
        // worth surfacing.
      }
      throw error;
    } finally {
      conn.release();
    }
  }

  // PGlite is a single in-process connection: BEGIN/COMMIT around the callback
  // is sufficient, and its query queue keeps statements ordered.
  await pglite.query('BEGIN');
  try {
    const result = await als.run(pglite, () => fn());
    await pglite.query('COMMIT');
    return result;
  } catch (error) {
    try {
      await pglite.query('ROLLBACK');
    } catch {
      // Ignore a failed rollback; surface the original error.
    }
    throw error;
  }
}

export async function runMigrations() {
  await getDb();
  await executor().query(
    `CREATE TABLE IF NOT EXISTS _migrations (
      name       text PRIMARY KEY,
      applied_at text NOT NULL DEFAULT (${NOW_ISO})
    )`
  );

  const applied = new Set(
    (await queryAll('SELECT name FROM _migrations')).map((row) => row.name)
  );

  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((file) => file.endsWith('.sql'))
    .sort();

  const executed = [];
  for (const file of files) {
    if (applied.has(file)) continue;
    const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
    await transaction(async () => {
      await exec(sql);
      await run('INSERT INTO _migrations (name) VALUES (?)', file);
    });
    executed.push(file);
  }
  return executed;
}
