import express from 'express';
import { queryAll, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness } from '../middleware/business.js';

export const notificationsRouter = express.Router();
notificationsRouter.use(requireAuth, requireBusiness);

function now() {
  return new Date().toISOString();
}

notificationsRouter.get('/', async (req, res) => {
  const notifications = await queryAll(
    'SELECT * FROM notifications WHERE business_id = ? ORDER BY created_at DESC LIMIT 200',
    req.business.id
  );
  const unreadCount = notifications.filter((n) => !n.read_at).length;
  res.json({
    notifications: notifications.map((n) => ({
      id: n.id,
      type: n.type,
      title: n.title,
      message: n.message,
      severity: n.severity,
      orderImportId: n.order_import_id,
      transactionId: n.transaction_id,
      readAt: n.read_at,
      createdAt: n.created_at,
    })),
    unreadCount,
  });
});

notificationsRouter.patch('/:id/read', async (req, res) => {
  await run(
    'UPDATE notifications SET read_at = ? WHERE id = ? AND business_id = ?',
    now(),
    req.params.id,
    req.business.id
  );
  res.json({ ok: true });
});

notificationsRouter.post('/read-all', async (req, res) => {
  await run(
    'UPDATE notifications SET read_at = ? WHERE business_id = ? AND read_at IS NULL',
    now(),
    req.business.id
  );
  res.json({ ok: true });
});

export default notificationsRouter;
