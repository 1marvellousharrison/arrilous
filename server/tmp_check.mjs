import('./src/db/index.js').then(async mod => {
  const db = await mod.getDb();
  // Test 1: simple query
  const r1 = await mod.queryOne('SELECT 1 AS test');
  console.log('queryOne 1:', JSON.stringify(r1));
  // Test 2: list tables via information_schema
  const r2 = await mod.queryAll(
    "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"
  );
  console.log('tables:', JSON.stringify(r2.rows));
  // Test 3: check if now_iso function exists
  const r3 = await mod.queryOne('SELECT now_iso() AS iso');
  console.log('now_iso:', JSON.stringify(r3));
});