import { runMigrations, closeDb } from './index.js';

try {
  const executed = await runMigrations();
  if (executed.length === 0) {
    console.log('No pending migrations. Database is up to date.');
  } else {
    console.log(`Applied ${executed.length} migration(s):`);
    for (const name of executed) console.log(`  - ${name}`);
  }
} catch (error) {
  console.error(`Migration error: ${error.message}`);
  process.exitCode = 1;
} finally {
  await closeDb();
}
