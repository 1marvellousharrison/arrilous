import express from 'express';

import { queryAll, queryOne } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusinessOwner, requireBusiness } from '../middleware/business.js';
import { publicTransaction } from './transactions.js';

export const dashboardRouter = express.Router();

/**
 * Phase 12 — the dashboard reads the database, never placeholder numbers.
 *
 * Every figure here is a conditional aggregate over `transactions`, scoped to
 * the caller's business by the same middleware as every other route.
 *
 * One decision worth stating, because it changes every number on the screen: a
 * cancelled transaction is excluded from the money totals. A cancelled sale did
 * not happen, so counting it as revenue would overstate what the business has
 * earned. It still gets its own count, so nothing disappears silently.
 */

const NOT_CANCELLED = "business_id = ? AND order_status <> 'cancelled'";

/**
 * The money for one staff member since a moment in time. Cancelled sales are
 * excluded for the same reason as the headline totals: they did not happen.
 */
async function staffTotalsSince(businessId, staffId, since) {
  const row = await queryOne(
    `SELECT
        COUNT(*)                        AS "transactionCount",
        COALESCE(SUM(total_kobo), 0)    AS "grossSalesKobo",
        COALESCE(SUM(CASE WHEN payment_status = 'paid'
                          THEN total_kobo ELSE 0 END), 0) AS "collectedKobo",
        COALESCE(SUM(CASE WHEN payment_status IN ('unpaid', 'payment_pending')
                          THEN total_kobo ELSE 0 END), 0) AS "outstandingKobo"
       FROM transactions
      WHERE business_id = ? AND created_by_user_id = ?
        AND order_status <> 'cancelled' AND created_at >= ?`,
    businessId,
    staffId,
    since
  );

  return {
    transactionCount: row?.transactionCount ?? 0,
    grossSalesKobo: row?.grossSalesKobo ?? 0,
    collectedKobo: row?.collectedKobo ?? 0,
    outstandingKobo: row?.outstandingKobo ?? 0,
  };
}

/**
 * The staff dashboard's periods, in the caller's own day. A sale at 00:30 in
 * Lagos must count as today even though the server stores UTC, so the client
 * sends its offset and the boundaries are shifted back to UTC here.
 */
async function staffPeriods(businessId, staffId, allTime, tzOffsetMinutes) {
  const offsetMs = tzOffsetMinutes * 60_000;
  const localNow = new Date(Date.now() + offsetMs);
  const todayStartLocal = Date.UTC(
    localNow.getUTCFullYear(),
    localNow.getUTCMonth(),
    localNow.getUTCDate()
  );
  const monthStartLocal = Date.UTC(localNow.getUTCFullYear(), localNow.getUTCMonth(), 1);
  const asUtc = (localMs) => new Date(localMs - offsetMs).toISOString();

  return {
    today: await staffTotalsSince(businessId, staffId, asUtc(todayStartLocal)),
    week: await staffTotalsSince(
      businessId,
      staffId,
      asUtc(todayStartLocal - 6 * 86_400_000)
    ),
    month: await staffTotalsSince(businessId, staffId, asUtc(monthStartLocal)),
    allTime,
  };
}


dashboardRouter.get('/summary', requireAuth, requireBusiness, async (req, res) => {
  const businessId = req.business.id;

  // A staff's home shows their own sales only; the owner sees the whole business.
  // Catalog and logistics figures stay business-wide — a staff can view the
  // catalog and still works the delivery desk, so those counts are not theirs to
  // have hidden.
  const staffId = req.staff ? req.auth.userId : null;
  const scopeSql = staffId ? ' AND created_by_user_id = ?' : '';
  const scopeParams = staffId ? [businessId, staffId] : [businessId];

  // What was sold, what was actually collected, and what is still owed.
  const money = await queryOne(
    `SELECT
        COUNT(*)                        AS "transactionCount",
        COALESCE(SUM(total_kobo), 0)    AS "grossSalesKobo",
        COALESCE(SUM(CASE WHEN payment_status = 'paid'
                          THEN total_kobo ELSE 0 END), 0) AS "collectedKobo",
        COALESCE(SUM(CASE WHEN payment_status IN ('unpaid', 'payment_pending')
                          THEN total_kobo ELSE 0 END), 0) AS "outstandingKobo"
       FROM transactions
      WHERE ${NOT_CANCELLED}${scopeSql}`,
    ...scopeParams
  );

  // One pass over the whole table for every state the dashboard reports.
  const counts = await queryOne(
    `SELECT
        COALESCE(SUM(CASE WHEN order_status = 'pending' THEN 1 ELSE 0 END), 0)
          AS "pendingOrder",
        COALESCE(SUM(CASE WHEN payment_status IN ('unpaid', 'payment_pending')
                          THEN 1 ELSE 0 END), 0)
          AS "pendingPayment",
        COALESCE(SUM(CASE WHEN delivery_status IN ('pending', 'accepted', 'picked_up')
                          THEN 1 ELSE 0 END), 0)
          AS "awaitingDelivery",
        COALESCE(SUM(CASE WHEN delivery_status = 'in_transit' THEN 1 ELSE 0 END), 0)
          AS "inTransit",
        COALESCE(SUM(CASE WHEN completion_status = 'completed' THEN 1 ELSE 0 END), 0)
          AS completed,
        COALESCE(SUM(CASE WHEN payment_status = 'failed' OR delivery_status = 'failed'
                          THEN 1 ELSE 0 END), 0)
          AS failed,
        COALESCE(SUM(CASE WHEN order_status = 'cancelled' THEN 1 ELSE 0 END), 0)
          AS cancelled
       FROM transactions
      WHERE business_id = ?${scopeSql}`,
    ...scopeParams
  );

  // Catalog and customer counts for the business card. Counting them here rather
  // than in the app means the card is right even when those lists are paginated
  // or not loaded at all.
  const catalog = await queryOne(
    `SELECT
        (SELECT COUNT(*) FROM products
          WHERE business_id = ? AND active = 1)      AS "activeProducts",
        (SELECT COUNT(*) FROM customers
          WHERE business_id = ?)                       AS customers`,
    businessId,
    businessId
  );

  const recent = (await queryAll(
    `SELECT * FROM transactions
      WHERE business_id = ?${scopeSql}
      ORDER BY created_at DESC
      LIMIT 8`,
    ...scopeParams
  )).map((row) => publicTransaction(row));

  // A staff member's home is their own workspace, not the owner's shop report.
  // The code, the day/week/month they have had, and the products they move most
  // all travel with the same summary call so the screen renders in one round
  // trip. The owner never receives these keys.
  let staff = null;
  let periods = null;
  let topProducts = [];
  if (staffId) {
    const profile = await queryOne(
      `SELECT sm.id, sm.staff_code, sm.status, sm.activated_at,
              u.full_name, u.phone,
              (SELECT COUNT(*) FROM transactions t
                WHERE t.created_by_user_id = sm.user_id
                  AND t.order_status <> 'cancelled') AS sales_count
         FROM staff_members sm
         JOIN users u ON u.id = sm.user_id
        WHERE sm.id = ?`,
      req.staff.id
    );

    staff = {
      id: profile?.id ?? req.staff.id,
      fullName: profile?.full_name ?? '',
      phone: profile?.phone ?? null,
      staffCode: profile?.staff_code ?? req.staff.staff_code,
      status: profile?.status ?? req.staff.status,
      activatedAt: profile?.activated_at ?? null,
      salesCount: profile?.sales_count ?? 0,
    };

    const allTime = {
      transactionCount: money?.transactionCount ?? 0,
      grossSalesKobo: money?.grossSalesKobo ?? 0,
      collectedKobo: money?.collectedKobo ?? 0,
      outstandingKobo: money?.outstandingKobo ?? 0,
    };
    const rawOffset = Number.parseInt(req.query.tz_offset_minutes, 10);
    const tzOffsetMinutes =
      Number.isFinite(rawOffset) && Math.abs(rawOffset) <= 14 * 60 ? rawOffset : 0;
    periods = await staffPeriods(businessId, staffId, allTime, tzOffsetMinutes);

    topProducts = await queryAll(
      `SELECT ti.product_name_snapshot AS name,
              SUM(ti.quantity)          AS quantity,
              SUM(ti.subtotal_kobo)     AS "revenueKobo"
         FROM transaction_items ti
         JOIN transactions t ON t.id = ti.transaction_id
        WHERE t.business_id = ? AND t.created_by_user_id = ?
          AND t.order_status <> 'cancelled'
        GROUP BY ti.product_name_snapshot
        ORDER BY quantity DESC, "revenueKobo" DESC
        LIMIT 5`,
      businessId,
      staffId
    );
  }

  // Spec 41 — the logistics strip. Every number is an aggregate, and the
  // "nearby" counts use the business's own pickup city so the figure means
  // something for this business rather than for the whole platform.
  const logistics = await logisticsSummary(businessId);

  res.json({
    totals: {
      transactionCount: money?.transactionCount ?? 0,
      grossSalesKobo: money?.grossSalesKobo ?? 0,
      collectedKobo: money?.collectedKobo ?? 0,
      outstandingKobo: money?.outstandingKobo ?? 0,
    },
    counts: {
      pendingOrder: counts?.pendingOrder ?? 0,
      pendingPayment: counts?.pendingPayment ?? 0,
      awaitingDelivery: counts?.awaitingDelivery ?? 0,
      inTransit: counts?.inTransit ?? 0,
      completed: counts?.completed ?? 0,
      failed: counts?.failed ?? 0,
      cancelled: counts?.cancelled ?? 0,
    },
    catalog: {
      activeProducts: catalog?.activeProducts ?? 0,
      customers: catalog?.customers ?? 0,
    },
    logistics,
    recent,
    ...(staff
      ? {
          staff,
          periods,
          topProducts,
        }
      : {}),
  });
});

/**
 * Spec 41 — pending requests, live deliveries, nearby supply and failures.
 *
 * "Nearby" is coverage of the business's pickup city: a provider on the other
 * side of the country is not nearby no matter how many vehicles it has. Supply
 * counts respect availability expiry, which is checked in `liveAvailability`
 * style here so a stale availability window never inflates the number.
 */
async function logisticsSummary(businessId) {
  const pickup = await queryOne('SELECT city FROM business_locations WHERE business_id = ?', businessId);
  const pickupCity = String(pickup?.city ?? '').trim();
  const now = new Date().toISOString();

  const requests = await queryOne(
    `SELECT
        COALESCE(SUM(CASE WHEN status IN ('requested', 'quoted') THEN 1 ELSE 0 END), 0) AS pending,
        COALESCE(SUM(CASE WHEN status IN ('accepted', 'assigned', 'picked_up', 'in_transit')
                            THEN 1 ELSE 0 END), 0) AS active,
        COALESCE(SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END), 0) AS failed
       FROM delivery_requests
      WHERE business_id = ?`,
    businessId
  );

  const nearbyProviders = pickupCity
    ? (await queryOne(
        `SELECT COUNT(DISTINCT o.id) AS count
           FROM logistics_organizations o
           JOIN logistics_service_areas a ON a.organization_id = o.id
          WHERE o.is_available = 1
            AND (o.availability_expires_at IS NULL OR o.availability_expires_at > ?)
            AND lower(a.city) = lower(?)`,
        now,
        pickupCity
      ))?.count ?? 0
    : 0;

  const nearbyRiders = pickupCity
    ? (await queryOne(
        `SELECT COUNT(DISTINCT r.id) AS count
           FROM logistics_riders r
           JOIN rider_service_areas a ON a.rider_id = r.id
          WHERE r.is_available = 1
            AND (r.availability_expires_at IS NULL OR r.availability_expires_at > ?)
            AND lower(a.city) = lower(?)`,
        now,
        pickupCity
      ))?.count ?? 0
    : 0;

  return {
    pendingRequests: requests?.pending ?? 0,
    activeDeliveries: requests?.active ?? 0,
    deliveryFailures: requests?.failed ?? 0,
    nearbyProviders,
    nearbyRiders,
  };
}

/**
 * Business profile and location for the dashboard card, in one call so the
 * screen does not have to wait on two requests to render.
 */
dashboardRouter.get('/business', requireAuth, requireBusinessOwner, async (req, res) => {
  const business = await queryOne(
    'SELECT * FROM businesses WHERE owner_user_id = ?',
    req.auth.userId
  );
  const location = business
    ? await queryOne('SELECT * FROM business_locations WHERE business_id = ?', business.id)
    : null;

  res.json({
    businessName: business?.business_name ?? null,
    businessCategory: business?.business_category ?? null,
    location: location
      ? {
          address: location.address,
          city: location.city,
          state: location.state,
          country: location.country,
          latitude: location.latitude,
          longitude: location.longitude,
        }
      : null,
  });
});