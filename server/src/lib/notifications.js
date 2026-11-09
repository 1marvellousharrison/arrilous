import crypto from 'node:crypto';

import { queryAll, queryOne, run } from '../db/index.js';

/**
 * The catalog's low-stock line.
 *
 * The app has always labelled a product "low" at five or fewer (see
 * `Product.isLowStock`), so the server uses the same number. One threshold in
 * two places is a bug waiting to happen, but the app's rule predates this
 * module; the constant is exported here so the server has a single place to
 * change it and the response carries the number to the client.
 */
export const LOW_STOCK_THRESHOLD = 5;

function severityFor(quantity) {
  return quantity <= 0 ? 'error' : 'warning';
}

function titleFor(quantity) {
  return quantity <= 0 ? 'Out of stock' : 'Low stock';
}

function messageFor(name, quantity) {
  return quantity <= 0
    ? `${name} is out of stock. Restock it before the next sale.`
    : `${name} has only ${quantity} left. Restock it soon.`;
}

/// Every active product at or below the threshold, emptiest first.
export async function lowStockRows(businessId) {
  return queryAll(
    `SELECT id, name, stock_quantity
       FROM products
      WHERE business_id = ? AND active = 1 AND stock_quantity <= ?
      ORDER BY stock_quantity ASC, lower(name) ASC`,
    businessId,
    LOW_STOCK_THRESHOLD
  );
}

/// The shape both the notification endpoint and the dashboard summary return.
export async function lowStockSummary(businessId) {
  const rows = await lowStockRows(businessId);
  return {
    count: rows.length,
    outOfStock: rows.filter((row) => row.stock_quantity <= 0).length,
    products: rows.map((row) => ({
      id: row.id,
      name: row.name,
      stockQuantity: row.stock_quantity,
      severity: severityFor(row.stock_quantity),
    })),
  };
}

/**
 * Makes the bell match the shelf.
 *
 * Called whenever the catalog or the inbox is read. A product that is low gets
 * one open alert; a product that is replenished has its open alert marked read.
 * Re-reading the inbox therefore does not pile up duplicates, and restocking is
 * what clears the warning rather than the owner merely opening the bell.
 */
export async function syncLowStockNotifications(businessId) {
  const rows = await lowStockRows(businessId);
  const current = new Map(rows.map((row) => [row.id, row]));
  const now = new Date().toISOString();

  const open = await queryAll(
    `SELECT id, product_id
       FROM notifications
      WHERE business_id = ? AND type = 'low_stock' AND read_at IS NULL`,
    businessId
  );

  for (const notification of open) {
    if (!notification.product_id || !current.has(notification.product_id)) {
      await run('UPDATE notifications SET read_at = ? WHERE id = ?', now, notification.id);
    }
  }

  for (const row of rows) {
    const severity = severityFor(row.stock_quantity);
    const title = titleFor(row.stock_quantity);
    const message = messageFor(row.name, row.stock_quantity);
    const existing = await queryOne(
      `SELECT id, severity, title, message
         FROM notifications
        WHERE business_id = ? AND type = 'low_stock'
          AND product_id = ? AND read_at IS NULL
        ORDER BY created_at DESC
        LIMIT 1`,
      businessId,
      row.id
    );

    if (!existing) {
      await run(
        `INSERT INTO notifications
           (id, business_id, user_id, product_id, type, title, message, severity, created_at)
         VALUES (?, ?, NULL, ?, 'low_stock', ?, ?, ?, ?)`,
        crypto.randomUUID(),
        businessId,
        row.id,
        title,
        message,
        severity,
        now
      );
      continue;
    }

    // A product that goes from "low" to "out" keeps one alert but changes its
    // severity and wording, and moves back to the top of the inbox.
    if (
      existing.severity !== severity ||
      existing.title !== title ||
      existing.message !== message
    ) {
      await run(
        `UPDATE notifications
            SET severity = ?, title = ?, message = ?, created_at = ?
          WHERE id = ?`,
        severity,
        title,
        message,
        now,
        existing.id
      );
    }
  }

  return lowStockSummary(businessId);
}

/// A single app alert. Errors and order-draft warnings use the same path so the
/// inbox has one shape no matter which part of the app raised it.
///
/// `userId` is the audience: NULL reaches everyone in the business, a user id
/// reaches only that person (the owner still sees all business rows).
/// `actorUserId` is a different question — who caused the event — so a sale a
/// staff member records can be business-wide news that still names them.
export async function addAppNotification({
  businessId,
  userId = null,
  actorUserId = null,
  importId = null,
  transactionId = null,
  productId = null,
  type,
  title,
  message,
  severity = 'info',
  createdAt = new Date().toISOString(),
}) {
  await run(
    `INSERT INTO notifications
       (id, business_id, user_id, actor_user_id, order_import_id, transaction_id,
        product_id, type, title, message, severity, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    crypto.randomUUID(),
    businessId,
    userId,
    actorUserId,
    importId,
    transactionId,
    productId,
    type,
    title,
    message,
    severity,
    createdAt
  );
}

/**
 * The same alert, but a failure to write it never breaks the business action
 * that raised it. A recorded sale must not be rolled back because the bell
 * could not be rung.
 */
export async function safeAddAppNotification(payload) {
  try {
    await addAppNotification(payload);
  } catch (error) {
    console.error(
      'Could not record notification:',
      error?.message || error,
      payload?.type
    );
  }
}

/// The name shown beside an event ("by Amina"). Returns null for a missing
/// user, so an event raised by a deleted account still renders.
export async function actorDisplayName(userId) {
  if (!userId) return null;
  const row = await queryOne('SELECT full_name FROM users WHERE id = ?', userId);
  return row?.full_name ?? null;
}

/// The notification shape the API returns. Both the inbox and a single staff's
/// activity feed use it, so a new field lands in both places at once.
export function publicNotification(row) {
  return {
    id: row.id,
    type: row.type,
    title: row.title,
    message: row.message,
    severity: row.severity,
    productId: row.product_id,
    orderImportId: row.order_import_id,
    transactionId: row.transaction_id,
    actorUserId: row.actor_user_id,
    actorName: row.actor_name ?? null,
    readAt: row.read_at,
    createdAt: row.created_at,
  };
}

/// Money as the inbox writes it: whole naira with thousands separators, and
/// kobo only when there are any. Kept here so server wording matches the app's
/// `formatKobo` closely enough to read as one product.
export function nairaText(kobo) {
  const value = Number(kobo) || 0;
  let naira = Math.floor(value / 100);
  let koboPart = Math.round(value - naira * 100);
  if (koboPart === 100) {
    naira += 1;
    koboPart = 0;
  }
  const grouped = String(naira).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return koboPart > 0
    ? `₦${grouped}.${String(koboPart).padStart(2, '0')}`
    : `₦${grouped}`;
}
