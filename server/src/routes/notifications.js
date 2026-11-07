import express from 'express';
import { queryAll, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness } from '../middleware/business.js';
import { syncLowStockNotifications } from '../lib/notifications.js';

export const notificationsRouter = express.Router();
notificationsRouter.use(requireAuth, requireBusiness);

function now() {
  return new Date().toISOString();
}

notificationsRouter.get('/', async (req, res) => {
  // Reading the inbox is also the moment the shelf is checked. Doing it here
  // means an owner who has not opened the product list still gets the warning,
  // and an owner who has restocked stops seeing it without clearing anything by
  // hand.
  const lowStock = await syncLowStockNotifications(req.business.id);

  const notifications = await queryAll(
    'SELECT * FROM notifications WHERE business_id = ? ORDER BY created_at DESC LIMIT 200',
    req.business.id
  );
  const unread = notifications.filter((n) => !n.read_at);
  const unreadCount = unread.length;
  const errorCount = unread.filter((n) => n.severity === 'error').length;
  const warningCount = unread.filter((n) => n.severity === 'warning').length;

  res.json({
    notifications: notifications.map((n) => ({
      id: n.id,
      type: n.type,
      title: n.title,
      message: n.message,
      severity: n.severity,
      productId: n.product_id,
      orderImportId: n.order_import_id,
      transactionId: n.transaction_id,
      readAt: n.read_at,
      createdAt: n.created_at,
    })),
    unreadCount,
    counts: {
      unread: unreadCount,
      lowStock: lowStock.count,
      outOfStock: lowStock.outOfStock,
      errors: errorCount,
      warnings: warningCount,
    },
    lowStock,
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
