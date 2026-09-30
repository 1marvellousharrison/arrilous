import express from 'express';
import cors from 'cors';
import { config } from './config.js';
import { authRouter } from './routes/auth.js';
import { notFoundHandler, errorHandler } from './middleware/errorHandler.js';
import { runMigrations, queryOne } from './db/index.js';

export function createApp({ migrate = true } = {}) {
  if (migrate) runMigrations();

  const app = express();
  app.set('trust proxy', true);
  app.disable('x-powered-by');

  app.use(
    cors({
      origin: config.cors.origins.includes('*') ? true : config.cors.origins,
      credentials: true,
    })
  );
  app.use(express.json({ limit: '100kb' }));

  app.get('/api/v1/health', (_req, res) => {
    let database = 'down';
    try {
      queryOne('SELECT 1 AS ok');
      database = 'up';
    } catch {
      database = 'down';
    }
    res.json({
      status: database === 'up' ? 'ok' : 'degraded',
      service: 'dee-api',
      version: '0.1.0',
      database,
      env: config.env,
      timestamp: new Date().toISOString(),
    });
  });

  app.use('/api/v1/auth', authRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
