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