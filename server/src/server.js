import { createApp } from './app.js';
import { config } from './config.js';
import { closeDb } from './db/index.js';

const app = await createApp();

const server = app.listen(config.port, config.host, () => {
  console.log(`dee-api listening on http://${config.host}:${config.port} (${config.env})`);
  console.log(`Health check: http://${config.host}:${config.port}/api/v1/health`);
});

function shutdown(signal) {
  console.log(`\n${signal} received, shutting down.`);
  server.close(() => {
    closeDb();
    process.exit(0);
  });
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
