import express from 'express';

import { queryAll, queryOne } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness, requireOwner } from '../middleware/business.js';
import { lowStockSummary } from '../lib/notifications.js';

export const analyticsRouter = express.Router();

const DAY_MS = 86_400_000;
const WEEKDAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const PAYMENT_ORDER = ['paid', 'unpaid', 'payment_pending', 'failed', 'refunded'];
const ORDER_ORDER = ['pending', 'confirmed', 'cancelled'];
const DELIVERY_ORDER = [
  'not_required',
  'pending',
  'accepted',
  'picked_up',
  'in_transit',
  'delivered',
  'failed',
];

function int(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.round(number) : 0;
}

/** The range the owner picks: a week, a month, or a quarter. */
function parseDays(value) {
  const days = Number.parseInt(value, 10);
  return [7, 30, 90].includes(days) ? days : 30;
}

/** The client's own clock, so "today" is the shop's today, not UTC's. */
function parseOffset(value) {
  const minutes = Number.parseInt(value, 10);
  return Number.isFinite(minutes) && Math.abs(minutes) <= 14 * 60 ? minutes : 0;
}

function localDateKey(iso, offsetMs) {
  const shifted = new Date(new Date(iso).getTime() + offsetMs);
  return shifted.toISOString().slice(0, 10);
}

function localParts(iso, offsetMs) {
  const shifted = new Date(new Date(iso).getTime() + offsetMs);
  return { weekday: shifted.getUTCDay(), hour: shifted.getUTCHours() };
}

function totalsFor(rows) {
  const live = rows.filter((row) => row.order_status !== 'cancelled');
  const revenueKobo = live.reduce((sum, row) => sum + int(row.total_kobo), 0);
  const orders = live.length;
  const collectedKobo = live
    .filter((row) => row.payment_status === 'paid')
    .reduce((sum, row) => sum + int(row.total_kobo), 0);
  const outstandingKobo = live
    .filter((row) => ['unpaid', 'payment_pending'].includes(row.payment_status))
    .reduce((sum, row) => sum + int(row.total_kobo), 0);

  return {
    revenueKobo,
    orders,
    averageOrderKobo: orders === 0 ? 0 : Math.round(revenueKobo / orders),
    collectedKobo,
    outstandingKobo,
  };
}

function statusMix(rows, field, order, { withAmount = false } = {}) {
  const buckets = new Map(order.map((status) => [status, { status, count: 0, amountKobo: 0 }]));
  for (const row of rows) {
    const status = row[field] ?? 'unknown';
    if (!buckets.has(status)) {
      buckets.set(status, { status, count: 0, amountKobo: 0 });
    }
    const bucket = buckets.get(status);
    bucket.count += 1;
    if (withAmount) bucket.amountKobo += int(row.total_kobo);
  }
  return [...buckets.values()].map((bucket) => ({
    status: bucket.status,
    count: bucket.count,
    ...(withAmount ? { amountKobo: bucket.amountKobo } : {}),
  }));
}

/**
 * The owner's analysis page: one request that answers "how is the business
 * doing" across money, products, customers, stock and delivery.
 *
 * The window is the owner's own week/month/quarter. Every figure is scoped to
 * the caller's business by `requireBusiness`, and only the owner may read it —
 * a staff member's home deliberately shows their own sales, not the shop's
 * whole financial picture.
 */
analyticsRouter.get(
  '/overview',
  requireAuth,
  requireBusiness,
  requireOwner,
  async (req, res) => {
    const businessId = req.business.id;
    const days = parseDays(req.query.days);
    const tzOffsetMinutes = parseOffset(req.query.tz_offset_minutes);
    const offsetMs = tzOffsetMinutes * 60_000;

    // Local midnight today, then the first local midnight of the window.
    const nowLocal = new Date(Date.now() + offsetMs);
    const todayStartLocal = Date.UTC(
      nowLocal.getUTCFullYear(),
      nowLocal.getUTCMonth(),
      nowLocal.getUTCDate()
    );
    const startLocal = todayStartLocal - (days - 1) * DAY_MS;
    const endLocal = todayStartLocal + DAY_MS;
    const asUtc = (localMs) => new Date(localMs - offsetMs).toISOString();

    const start = asUtc(startLocal);
    const end = asUtc(endLocal);
    const previousStart = asUtc(startLocal - days * DAY_MS);

    const rows = await queryAll(
      `SELECT customer_id, total_kobo, payment_status, order_status,
              delivery_status, completion_status, created_at
         FROM transactions
        WHERE business_id = ? AND created_at >= ? AND created_at < ?
        ORDER BY created_at ASC`,
      businessId,
      start,
      end
    );

    const previousRows = await queryAll(
      `SELECT total_kobo, order_status
         FROM transactions
        WHERE business_id = ? AND created_at >= ? AND created_at < ?`,
      businessId,
      previousStart,
      start
    );

    const totals = totalsFor(rows);
    const previous = totalsFor(previousRows);
    const liveRows = rows.filter((row) => row.order_status !== 'cancelled');

    // One bucket per local day, including quiet days, so the trend line has a
    // continuous shape instead of skipping gaps.
    const daily = [];
    const dailyIndex = new Map();
    for (let i = 0; i < days; i += 1) {
      const date = new Date(startLocal + i * DAY_MS).toISOString().slice(0, 10);
      dailyIndex.set(date, daily.length);
      daily.push({ date, revenueKobo: 0, orders: 0 });
    }
    for (const row of liveRows) {
      const index = dailyIndex.get(localDateKey(row.created_at, offsetMs));
      if (index === undefined) continue;
      daily[index].revenueKobo += int(row.total_kobo);
      daily[index].orders += 1;
    }

    const weekdays = WEEKDAY_LABELS.map((label, weekday) => ({
      weekday,
      label,
      revenueKobo: 0,
      orders: 0,
    }));
    const hours = Array.from({ length: 24 }, (_, hour) => ({
      hour,
      revenueKobo: 0,
      orders: 0,
    }));
    for (const row of liveRows) {
      const { weekday, hour } = localParts(row.created_at, offsetMs);
      weekdays[weekday].revenueKobo += int(row.total_kobo);
      weekdays[weekday].orders += 1;
      hours[hour].revenueKobo += int(row.total_kobo);
      hours[hour].orders += 1;
    }
    const peakHour = hours.reduce(
      (best, item) => (item.orders > best.orders ? item : best),
      hours[0]
    );

    const topProducts = (
      await queryAll(
        `SELECT ti.product_name_snapshot AS name,
                SUM(ti.quantity)            AS quantity,
                SUM(ti.subtotal_kobo)       AS "revenueKobo"
           FROM transaction_items ti
           JOIN transactions t ON t.id = ti.transaction_id
          WHERE t.business_id = ? AND t.order_status <> 'cancelled'
            AND t.created_at >= ? AND t.created_at < ?
          GROUP BY ti.product_name_snapshot
          ORDER BY "revenueKobo" DESC, quantity DESC
          LIMIT 6`,
        businessId,
        start,
        end
      )
    ).map((row) => ({
      name: row.name,
      quantity: int(row.quantity),
      revenueKobo: int(row.revenueKobo),
    }));

    // Customers are split into people who were already on file and people the
    // shop met inside this window. A walk-in sale has no customer record, so it
    // gets its own count instead of being attributed to nobody.
    const buyerIds = new Set(
      liveRows.map((row) => row.customer_id).filter((id) => id != null)
    );
    const customerRows = await queryAll(
      'SELECT id, created_at FROM customers WHERE business_id = ?',
      businessId
    );
    const customerCreatedAt = new Map(
      customerRows.map((customer) => [customer.id, customer.created_at])
    );
    let newCustomers = 0;
    let returning = 0;
    for (const id of buyerIds) {
      const created = customerCreatedAt.get(id);
      if (created != null && created >= start) newCustomers += 1;
      else returning += 1;
    }

    const topCustomers = (
      await queryAll(
        `SELECT COALESCE(c.name, 'Walk-in customer') AS name,
                COUNT(*)                             AS orders,
                COALESCE(SUM(t.total_kobo), 0)       AS "spentKobo"
           FROM transactions t
           LEFT JOIN customers c ON c.id = t.customer_id
          WHERE t.business_id = ? AND t.order_status <> 'cancelled'
            AND t.created_at >= ? AND t.created_at < ?
          GROUP BY c.id, c.name
          ORDER BY "spentKobo" DESC
          LIMIT 5`,
        businessId,
        start,
        end
      )
    ).map((row) => ({
      name: row.name,
      orders: int(row.orders),
      spentKobo: int(row.spentKobo),
    }));

    const lowStock = await lowStockSummary(businessId);
    const inventoryRow = await queryOne(
      `SELECT COUNT(*) AS "activeProducts",
              COALESCE(SUM(price_kobo * stock_quantity), 0) AS "inventoryValueKobo"
         FROM products
        WHERE business_id = ? AND active = 1`,
      businessId
    );

    const deliveryRow = await queryOne(
      `SELECT COUNT(*) AS requests,
              COALESCE(SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END), 0) AS delivered,
              COALESCE(SUM(CASE WHEN status IN ('failed', 'declined', 'cancelled')
                                THEN 1 ELSE 0 END), 0) AS failed
         FROM delivery_requests
        WHERE business_id = ? AND created_at >= ? AND created_at < ?`,
      businessId,
      start,
      end
    );
    const delivered = int(deliveryRow?.delivered);
    const failed = int(deliveryRow?.failed);
    const finished = delivered + failed;

    const paymentRows = liveRows;

    res.json({
      range: { days, start, end, tzOffsetMinutes },
      totals,
      previous,
      daily,
      weekdays,
      hours,
      peakHour,
      topProducts,
      paymentMix: statusMix(paymentRows, 'payment_status', PAYMENT_ORDER, { withAmount: true }),
      orderMix: statusMix(rows, 'order_status', ORDER_ORDER),
      deliveryMix: statusMix(rows, 'delivery_status', DELIVERY_ORDER),
      customers: {
        buyers: buyerIds.size,
        newCustomers,
        returning,
        walkInOrders: liveRows.filter((row) => row.customer_id == null).length,
        top: topCustomers,
      },
      inventory: {
        activeProducts: int(inventoryRow?.activeProducts),
        inventoryValueKobo: int(inventoryRow?.inventoryValueKobo),
        lowStock: lowStock.count,
        outOfStock: lowStock.outOfStock,
        products: lowStock.products,
      },
      logistics: {
        requests: int(deliveryRow?.requests),
        delivered,
        failed,
        successRate: finished === 0 ? null : Math.round((delivered / finished) * 100),
      },
      generatedAt: new Date().toISOString(),
    });
  }
);

export default analyticsRouter;
