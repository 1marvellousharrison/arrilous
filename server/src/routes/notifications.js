import express from 'express';
import { queryAll, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness } from '../middleware/business.js';
import {
  publicNotification,
  syncLowStockNotifications,
} from '../lib/notifications.js';

export const notificationsRouter = express.Router();
notificationsRouter.use(requireAuth, requireBusiness);

function now() {
  return new Date().toISOString();
}

/**
 * The inbox is complete history, not a sampled feed, so the client can filter
 * it by day, week, month or year without another round trip. 500 is generous
 * for a busy shop while still bounding a single response.
 */
function inboxLimit(value) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return 500;
  return Math.min(Math.max(parsed, 1), 500);
}

/**
 * Audience rules.
 *
 * `user_id IS NULL` is business-wide news; a user id is a message for that one
 * person. A staff member sees business-wide rows plus their own. The owner is
 * the business: they see every row, including staff-only draft alerts.
 */
function audience(req) {
  return req.staff
    ? { clause: ' AND (n.user_id IS NULL OR n.user_id = ?)', params: [req.staff.user_id] }
    : { clause: '', params: [] };
}

notificationsRouter.get('/', async (req, res) => {
  // Reading the inbox is also the moment the shelf is checked. Doing it here
  // means an owner who has not opened the product list still gets the warning,
  // and an owner who has restocked stops seeing it without clearing anything by
  // hand.
  const lowStock = await syncLowStockNotifications(req.business.id);
  const scope = audience(req);

  const rows = await queryAll(
    `SELECT n.*, u.full_name AS actor_name
       FROM notifications n
       LEFT JOIN users u ON u.id = n.actor_user_id
      WHERE n.business_id = ?${scope.clause}
      ORDER BY n.created_at DESC
      LIMIT ?`,
    req.business.id,
    ...scope.params,
    inboxLimit(req.query.limit)
  );
  const unread = rows.filter((n) => !n.read_at);
  const unreadCount = unread.length;
  const errorCount = unread.filter((n) => n.severity === 'error').length;
  const warningCount = unread.filter((n) => n.severity === 'warning').length;

  res.json({
    notifications: rows.map(publicNotification),
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
  if (req.staff) {
    await run(
      `UPDATE notifications
          SET read_at = ?
        WHERE id = ? AND business_id = ?
          AND (user_id IS NULL OR user_id = ?)`,
      now(),
      req.params.id,
      req.business.id,
      req.staff.user_id
    );
  } else {
    await run(
      'UPDATE notifications SET read_at = ? WHERE id = ? AND business_id = ?',
      now(),
      req.params.id,
      req.business.id
    );
  }
  res.json({ ok: true });
});

/**
 * Opening the inbox is itself the act of reading it, so the routine alerts are
 * cleared without the owner tapping each one. Two kinds deliberately survive:
 *
 *  - low-stock alerts, which stay in the shelf count until the product is
 *    actually restocked (or archived);
 *  - errors, which mean something went wrong and should not disappear just
 *    because the page was opened.
 *
 * `include_important: true` remains available for an explicit "clear everything"
 * request.
 */
notificationsRouter.post('/read-all', async (req, res) => {
  const includeImportant = req.body?.include_important === true;
  const importantClause = includeImportant
    ? ''
    : " AND type <> 'low_stock' AND severity <> 'error'";
  const scope = req.staff
    ? ' AND (user_id IS NULL OR user_id = ?)'
    : '';
  await run(
    `UPDATE notifications
        SET read_at = ?
      WHERE business_id = ? AND read_at IS NULL${importantClause}${scope}`,
    now(),
    req.business.id,
    ...(req.staff ? [req.staff.user_id] : [])
  );
  res.json({ ok: true, keptImportant: !includeImportant });
});

export default notificationsRouter;
