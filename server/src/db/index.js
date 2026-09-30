import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { config } from '../config.js';

const MIGRATIONS_DIR = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  'migrations'
);

let db;

function ensureDir(filePath) {
  if (filePath === ':memory:') return;
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

/**
 * Opens (and memoises) the SQLite connection, applying pragmas that matter for
 * a small multi-user API: WAL for concurrent reads, foreign_keys so the
 * ON DELETE CASCADE rules in migrations are actually enforced.
 */
export function getDb() {
  if (db) return db;
  ensureDir(config.databasePath);
  db = new DatabaseSync(config.databasePath);
  db.exec('PRAGMA journal_mode = WAL;');
  db.exec('PRAGMA foreign_keys = ON;');
  db.exec('PRAGMA busy_timeout = 5000;');
  return db;
}

export function closeDb() {
  if (db) {
    db.close();
    db = undefined;
  }
}

export function runMigrations() {
  const conn = getDb();
  conn.exec(`CREATE TABLE IF NOT EXISTS _migrations (
    name       TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
  );`);

  const applied = new Set(
    conn
      .prepare('SELECT name FROM _migrations')
      .all()
      .map((row) => row.name)
  );

  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  const executed = [];
  for (const file of files) {
    if (applied.has(file)) continue;
    const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
    conn.exec('BEGIN');
    try {
      conn.exec(sql);
      conn.prepare('INSERT INTO _migrations (name) VALUES (?)').run(file);
      conn.exec('COMMIT');
      executed.push(file);
    } catch (error) {
      conn.exec('ROLLBACK');
      throw new Error(`Migration ${file} failed: ${error.message}`);
    }
  }
  return executed;
}

export function queryOne(sql, ...params) {
  const row = getDb().prepare(sql).get(...params);
  return row ? { ...row } : undefined;
}

export function queryAll(sql, ...params) {
  return getDb()
    .prepare(sql)
    .all(...params)
    .map((row) => ({ ...row }));
}

export function run(sql, ...params) {
  return getDb()
    .prepare(sql)
    .run(...params);
}

export function transaction(fn) {
  const conn = getDb();
  conn.exec('BEGIN');
  try {
    const result = fn();
    conn.exec('COMMIT');
    return result;
  } catch (error) {
    conn.exec('ROLLBACK');
    throw error;
  }
}
