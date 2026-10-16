import express from 'express';
import cors from 'cors';
import { config } from './config.js';
import { authRouter } from './routes/auth.js';
import { businessRouter } from './routes/business.js';
import { productRouter } from './routes/products.js';
import { customerRouter } from './routes/customers.js';
import { transactionRouter } from './routes/transactions.js';
import { dashboardRouter } from './routes/dashboard.js';
import { logisticsRouter } from './routes/logistics.js';
import { walletRouter } from './routes/wallet.js';
import { staffRouter } from './routes/staff.js';
import { notFoundHandler, errorHandler } from './middleware/errorHandler.js';
import { runMigrations, queryOne } from './db/index.js';

export async function createApp({ migrate = true } = {}) {
  if (migrate) await runMigrations();

  const app = express();
  app.set('trust proxy', true);
  app.disable('x-powered-by');

  app.use(
    cors({
      origin: config.cors.origins.includes('*') ? true : config.cors.origins,
      credentials: true,
    })
  );
  // A little headroom for the optional business logo, which rides along as a
  // downscaled image data URL and can approach a few hundred kilobytes.
  app.use(express.json({ limit: '1mb' }));

  app.get('/api/v1/health', async (_req, res) => {
    let database = 'down';
    try {
      await queryOne('SELECT 1 AS ok');
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
  app.use('/api/v1/business', businessRouter);
  app.use('/api/v1/products', productRouter);
  app.use('/api/v1/customers', customerRouter);
  app.use('/api/v1/transactions', transactionRouter);
  // Phase 12 — dashboard aggregates. Mounted under /dashboard rather than on
  // /transactions so the reporting queries stay separate from the CRUD surface.
  app.use('/api/v1/dashboard', dashboardRouter);
  app.use('/api/v1/logistics', logisticsRouter);
  app.use('/api/v1/wallet', walletRouter);
  app.use('/api/v1/staff', staffRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
