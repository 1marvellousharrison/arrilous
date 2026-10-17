import express from 'express';
import crypto from 'node:crypto';
import { queryAll, queryOne, run, transaction } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness, findBusinessForUser } from '../middleware/business.js';
import { requireRole } from '../middleware/roles.js';
import { badRequest, conflict, forbidden, notFound, validationFailed } from '../lib/errors.js';
import {
  logisticsOrganizationSchema, availabilitySchema, serviceAreaSchema, pricingSchema,
  vehicleCreateSchema, riderModeCreateSchema, deliveryRequestSchema, quoteSchema,
  assignmentSchema, deliveryUpdateSchema, confirmationSchema, riderAssignmentSchema,
  availabilityAdjustSchema, deliveryOtpSchema, toFieldErrors, riderProfileSchema,
} from '../lib/validators.js';
import { config } from '../config.js';
import { assertTransition, assertStatusCombination } from '../lib/statuses.js';
import { currentAxes, recordStatusDiff } from '../lib/history.js';

export const logisticsRouter = express.Router();

function parse(schema, payload) {
  const result = schema.safeParse(payload ?? {});
  if (!result.success) throw validationFailed(toFieldErrors(result.error));
  return result.data;
}

function liveAvailability(row) {
  return Boolean(row.is_available) && (!row.availability_expires_at || new Date(row.availability_expires_at) > new Date());
}

async function expireAvailability() {
  const now = new Date().toISOString();
  await run('UPDATE logistics_organizations SET is_available = 0, updated_at = ? WHERE is_available = 1 AND availability_expires_at IS NOT NULL AND availability_expires_at <= ?', now, now);
  await run('UPDATE logistics_riders SET is_available = 0, updated_at = ? WHERE is_available = 1 AND availability_expires_at IS NOT NULL AND availability_expires_at <= ?', now, now);
}

// Spec 16/17 v2 — a provider picks the exact time of day their shift ends
// (activation asks "work until", not "how many hours"). Every closing time
// flows through the same rule: explicit `availability_expires_at`, the day's
// `planned_hours`, or a fixed 8-hour default. `planned_hours` is kept for
// display and is ALWAYS calculated between the current time and the closing
// time — "until 5pm from now" — so a re-plan or an adjustment stays honest.
const DEFAULT_PLANNED_HOURS = 8;
const HOUR_MS = 3_600_000;

/**
 * Returns the four availability columns for the next stored row. `body` is the
 * parsed availability payload. Activation always writes a closing time — an
 * explicit `availability_expires_at` (the client's "work until"), the day's
 * `planned_hours`, or a fixed 8-hour default — so an account can never stay
 * available until it is turned off. The shift is measured from the current
 * time to that closing time, never from an earlier start.
 */
function availabilityNext(profile, body) {
  const now = new Date();
  if (!body.is_available) {
    return { is_available: 0, started_at: null, expires_at: null, planned_hours: null };
  }
  const startedAt = now.toISOString();
  let target;
  let plannedHours;
  if (body.planned_hours != null) {
    target = new Date(now.getTime() + body.planned_hours * HOUR_MS);
    plannedHours = body.planned_hours;
  } else if (body.availability_expires_at != null) {
    target = new Date(body.availability_expires_at);
    plannedHours = Math.min(24, Math.max(1, Math.round((target.getTime() - now.getTime()) / HOUR_MS)));
  } else {
    target = new Date(now.getTime() + DEFAULT_PLANNED_HOURS * HOUR_MS);
    plannedHours = DEFAULT_PLANNED_HOURS;
  }
  // A schedule that is already behind "now" ends the shift rather than writing
  // a closing time that liveAvailability would instantly reject.
  if (target.getTime() <= now.getTime()) {
    return { is_available: 0, started_at: null, expires_at: null, planned_hours: null };
  }
  return {
    is_available: 1,
    started_at: startedAt,
    expires_at: target.toISOString(),
    planned_hours: plannedHours,
  };
}

/**
 * Applies a signed minute adjustment to today's shift: positive lengthens the
 * closing time, negative trims it. A trim that would pull the closing time to
 * or before "now" closes the shift immediately. The kept plan is recalculated
 * from the current time to the new closing time, exactly as on activation.
 */
function adjustAvailability(profile, minutes) {
  const now = Date.now();
  const base = profile.availability_expires_at
    ? new Date(profile.availability_expires_at).getTime()
    : now;
  const target = new Date(base + minutes * 60_000);
  if (target.getTime() <= now) {
    return { is_available: 0, started_at: null, expires_at: null, planned_hours: null };
  }
  return {
    is_available: 1,
    started_at: profile.availability_started_at || new Date(now).toISOString(),
    expires_at: target.toISOString(),
    planned_hours: Math.min(24, Math.max(1, Math.round((target.getTime() - now) / HOUR_MS))),
  };
}

async function event(requestId, actorUserId, eventType, note = null) {
  await run('INSERT INTO delivery_request_events (id, delivery_request_id, actor_user_id, event_type, note) VALUES (?, ?, ?, ?, ?)', crypto.randomUUID(), requestId, actorUserId, eventType, note);
}

// Spec 40 — a vehicle held by an assignment keeps counting as assigned until it
// is released, and released vehicles are given back. Doing this once here keeps
// the counter truthful across every path that can end a delivery (delivered,
// failed, declined, retry) instead of at each of those call sites.
async function releaseRequestVehicles(requestId, actorUserId) {
  const held = await queryAll(
    'SELECT vehicle_id FROM delivery_assignments WHERE delivery_request_id = ? AND released_at IS NULL AND vehicle_id IS NOT NULL',
    requestId,
  );
  if (held.length === 0) return;
  const now = new Date().toISOString();
  for (const assignment of held) {
    await run(
      'UPDATE logistics_vehicles SET available_quantity = LEAST(total_quantity, available_quantity + 1), updated_at = ? WHERE id = ?',
      now,
      assignment.vehicle_id,
    );
  }
  await run(
    'UPDATE delivery_assignments SET released_at = ? WHERE delivery_request_id = ? AND released_at IS NULL',
    now,
    requestId,
  );
  if (actorUserId) await event(requestId, actorUserId, 'vehicles_released');
}

async function notify(userId, requestId, kind, title, body) {
  if (!userId) return;
  await run('INSERT INTO logistics_notifications (id, user_id, delivery_request_id, kind, title, body) VALUES (?, ?, ?, ?, ?, ?)', crypto.randomUUID(), userId, requestId, kind, title, body);
}

async function requestRecipients(request) {
  const businessOwner = (await queryOne('SELECT owner_user_id FROM businesses WHERE id = ?', request.business_id))?.owner_user_id;
  const organizationOwner = request.organization_id ? (await queryOne('SELECT owner_user_id FROM logistics_organizations WHERE id = ?', request.organization_id))?.owner_user_id : null;
  // Spec 40 — being handed the job through an assignment counts the same as
  // being named on the request itself.
  const riderId = request.rider_id
    ?? (await queryOne('SELECT rider_id FROM delivery_assignments WHERE delivery_request_id = ? AND released_at IS NULL AND rider_id IS NOT NULL', request.id))?.rider_id
    ?? null;
  const riderUser = riderId ? (await queryOne('SELECT user_id FROM logistics_riders WHERE id = ?', riderId))?.user_id : null;
  return { businessOwner, organizationOwner, riderUser };
}

function publicOrganization(row) {
  if (!row) return null;
  return {
    id: row.id, name: row.name, phone: row.phone, email: row.email, category: row.category,
    description: row.description,
    isAvailable: liveAvailability(row), availabilityExpiresAt: row.availability_expires_at,
    availabilityStartedAt: row.availability_started_at, plannedHours: row.planned_hours,
    createdAt: row.created_at, updatedAt: row.updated_at,
  };
}

function publicRider(row) {
  if (!row) return null;
  return {
    id: row.id, userId: row.user_id, organizationId: row.organization_id,
    fullName: row.full_name, phone: row.phone, category: row.category, description: row.description,
    isAvailable: liveAvailability(row),
    availabilityExpiresAt: row.availability_expires_at,
    availabilityStartedAt: row.availability_started_at, plannedHours: row.planned_hours,
  };
}

function publicRequest(row) {
  return {
    id: row.id, transactionId: row.transaction_id, transactionNumber: row.transaction_number,
    businessId: row.business_id, businessName: row.business_name,
    organizationId: row.organization_id, organizationName: row.organization_name,
    riderId: row.rider_id, riderName: row.rider_name, pickupAddress: row.pickup_address,
    pickupCity: row.pickup_city, destinationAddress: row.destination_address,
    destinationCity: row.destination_city, packageDescription: row.package_description,
    packageSize: row.package_size, preferredMode: row.preferred_mode,
    publishedPriceKobo: row.published_price_kobo, quotedPriceKobo: row.quoted_price_kobo,
    acceptedPriceKobo: row.accepted_price_kobo, status: row.status,
    failureReason: row.failure_reason, createdAt: row.created_at, updatedAt: row.updated_at,
  };
}

async function organizationForUser(userId) {
  return await queryOne('SELECT * FROM logistics_organizations WHERE owner_user_id = ?', userId);
}

async function riderForUser(userId) {
  return await queryOne(`SELECT r.*, u.full_name, u.phone FROM logistics_riders r
    JOIN users u ON u.id = r.user_id WHERE r.user_id = ?`, userId);
}

async function requireOrganization(req) {
  const org = await organizationForUser(req.auth.userId);
  if (!org) throw notFound('Create your logistics organization profile first.');
  return org;
}

async function requireRider(req) {
  const rider = await riderForUser(req.auth.userId);
  if (!rider) throw notFound('Create your rider profile first.');
  return rider;
}

async function requestRow(id) {
  const row = await queryOne(`SELECT d.*, t.transaction_number, b.business_name,
      o.name AS organization_name, u.full_name AS rider_name
    FROM delivery_requests d
    JOIN transactions t ON t.id = d.transaction_id
    JOIN businesses b ON b.id = d.business_id
    LEFT JOIN logistics_organizations o ON o.id = d.organization_id
    LEFT JOIN logistics_riders r ON r.id = COALESCE(d.rider_id, (SELECT a.rider_id FROM delivery_assignments a WHERE a.delivery_request_id = d.id AND a.released_at IS NULL AND a.rider_id IS NOT NULL))
    LEFT JOIN users u ON u.id = r.user_id
    WHERE d.id = ?`, id);
  if (!row) throw notFound('That delivery request does not exist.');
  return row;
}

async function requestForBusiness(id, businessId) {
  const row = await requestRow(id);
  if (row.business_id !== businessId) throw notFound('That delivery request does not exist.');
  return row;
}

async function updateTransactionDelivery(transactionId, nextDeliveryStatus, userId) {
  const current = await queryOne('SELECT * FROM transactions WHERE id = ?', transactionId);
  if (!current || current.delivery_status === nextDeliveryStatus) return;
  assertTransition('delivery', current.delivery_status, nextDeliveryStatus);
  assertStatusCombination({
    orderStatus: current.order_status, paymentStatus: current.payment_status,
    deliveryStatus: nextDeliveryStatus, completionStatus: current.completion_status,
    deliveryRequired: Boolean(current.delivery_required),
  }, {
    orderStatus: current.order_status, paymentStatus: current.payment_status,
    deliveryStatus: current.delivery_status, completionStatus: current.completion_status,
  });
  await run('UPDATE transactions SET delivery_status = ?, updated_at = ? WHERE id = ?', nextDeliveryStatus, new Date().toISOString(), current.id);
  await recordStatusDiff({
    transactionId: current.id, businessId: current.business_id, userId,
    previous: currentAxes(current),
    next: { order: current.order_status, payment: current.payment_status, delivery: nextDeliveryStatus, completion: current.completion_status },
    note: 'Updated from delivery workflow.',
  });
}

async function organizationDetails(org) {
  return {
    organization: publicOrganization(org),
    serviceAreas: await queryAll('SELECT * FROM logistics_service_areas WHERE organization_id = ? ORDER BY city, area', org.id),
    pricing: (await queryAll('SELECT * FROM logistics_pricing WHERE organization_id = ? ORDER BY destination', org.id)).map((row) => ({ ...row, priceKobo: row.price_kobo })),
    vehicles: (await queryAll('SELECT * FROM logistics_vehicles WHERE organization_id = ? ORDER BY vehicle_type', org.id)).map((row) => ({ ...row, totalQuantity: row.total_quantity, availableQuantity: row.available_quantity, startingPriceKobo: row.starting_price_kobo, isActive: Boolean(row.active) })),
  };
}

logisticsRouter.use(requireAuth);

// Availability expiration is persisted before every logistics read or write.
// Expiration affects only matching; assignments and active deliveries remain.
logisticsRouter.use(async (_req, _res, next) => { await expireAvailability(); next(); });

logisticsRouter.get('/notifications', async (req, res) => {
  const notifications = (await queryAll('SELECT * FROM logistics_notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 100', req.auth.userId)).map((row) => ({
    id: row.id, deliveryRequestId: row.delivery_request_id, kind: row.kind, title: row.title,
    body: row.body, readAt: row.read_at, createdAt: row.created_at,
  }));
  res.json({ notifications, unreadCount: notifications.filter((item) => !item.readAt).length });
});

logisticsRouter.patch('/notifications/:id/read', async (req, res) => {
  await run('UPDATE logistics_notifications SET read_at = ? WHERE id = ? AND user_id = ?', new Date().toISOString(), req.params.id, req.auth.userId);
  res.status(204).end();
});

// Logistics organization profile, availability, service coverage, pricing, and fleet.
logisticsRouter.get('/organization', requireRole('logistics_partner'), async (req, res) => {
  // 404 (not 500) for a partner who has not created the profile yet: the app
  // treats a missing profile as "show setup", and a 500 would look like a fault.
  const org = await requireOrganization(req);
  res.json({ ...(await organizationDetails(org)), organization: publicOrganization(org) });
});

logisticsRouter.post('/organization', requireRole('logistics_partner'), async (req, res) => {
  if (await organizationForUser(req.auth.userId)) throw conflict('This account already has an organization.', 'organization_exists');
  const body = parse(logisticsOrganizationSchema, req.body);
  const id = crypto.randomUUID();
  await run('INSERT INTO logistics_organizations (id, owner_user_id, name, phone, email, description, category) VALUES (?, ?, ?, ?, ?, ?, ?)', id, req.auth.userId, body.name, body.phone, body.email ?? null, body.description, body.category);
  res.status(201).json(await organizationDetails(await queryOne('SELECT * FROM logistics_organizations WHERE id = ?', id)));
});

logisticsRouter.patch('/organization/availability', requireRole('logistics_partner'), async (req, res) => {
  const body = parse(availabilitySchema, req.body); const org = await requireOrganization(req);
  const next = availabilityNext(org, body);
  await run('UPDATE logistics_organizations SET is_available = ?, availability_started_at = ?, availability_expires_at = ?, planned_hours = ?, updated_at = ? WHERE id = ?', next.is_available, next.started_at, next.expires_at, next.planned_hours, new Date().toISOString(), org.id);
  res.json({ organization: publicOrganization(await queryOne('SELECT * FROM logistics_organizations WHERE id = ?', org.id)) });
});
logisticsRouter.post('/organization/availability/extend', requireRole('logistics_partner'), async (req, res) => {
  const body = parse(availabilityAdjustSchema, req.body); const org = await requireOrganization(req);
  if (!liveAvailability(org)) throw badRequest('Become available before changing your closing time.');
  const next = adjustAvailability(org, body.minutes);
  await run('UPDATE logistics_organizations SET is_available = ?, availability_started_at = ?, availability_expires_at = ?, planned_hours = ?, updated_at = ? WHERE id = ?', next.is_available, next.started_at, next.expires_at, next.planned_hours, new Date().toISOString(), org.id);
  res.json({ organization: publicOrganization(await queryOne('SELECT * FROM logistics_organizations WHERE id = ?', org.id)) });
});

logisticsRouter.get('/organization/areas', requireRole('logistics_partner'), async (req, res) => res.json({ serviceAreas: await queryAll('SELECT * FROM logistics_service_areas WHERE organization_id = ? ORDER BY city, area', (await requireOrganization(req)).id) }));
logisticsRouter.post('/organization/areas', requireRole('logistics_partner'), async (req, res) => {
  const body = parse(serviceAreaSchema, req.body); const org = await requireOrganization(req); const id = crypto.randomUUID();
  await run('INSERT INTO logistics_service_areas (id, organization_id, city, area, state, country, latitude, longitude, radius_km) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', id, org.id, body.city, body.area ?? null, body.state ?? null, body.country ?? null, body.latitude ?? null, body.longitude ?? null, body.radius_km ?? null);
  res.status(201).json({ serviceArea: await queryOne('SELECT * FROM logistics_service_areas WHERE id = ?', id) });
});
logisticsRouter.get('/organization/pricing', requireRole('logistics_partner'), async (req, res) => res.json({ pricing: (await organizationDetails(await requireOrganization(req))).pricing }));
logisticsRouter.post('/organization/pricing', requireRole('logistics_partner'), async (req, res) => {
  const body = parse(pricingSchema, req.body); const org = await requireOrganization(req); const existing = await queryOne('SELECT id FROM logistics_pricing WHERE organization_id = ? AND destination = ? AND vehicle_type IS NOT DISTINCT FROM ?', org.id, body.destination, body.vehicle_type ?? null); const id = existing?.id ?? crypto.randomUUID();
  if (existing) await run('UPDATE logistics_pricing SET price_kobo = ?, updated_at = ? WHERE id = ?', body.price_kobo, new Date().toISOString(), id);
  else await run('INSERT INTO logistics_pricing (id, organization_id, destination, price_kobo, vehicle_type) VALUES (?, ?, ?, ?, ?)', id, org.id, body.destination, body.price_kobo, body.vehicle_type ?? null);
  res.status(existing ? 200 : 201).json({ pricing: await queryOne('SELECT * FROM logistics_pricing WHERE id = ?', id) });
});
logisticsRouter.get('/organization/vehicles', requireRole('logistics_partner'), async (req, res) => res.json({ vehicles: (await organizationDetails(await requireOrganization(req))).vehicles }));
logisticsRouter.post('/organization/vehicles', requireRole('logistics_partner'), async (req, res) => {
  const body = parse(vehicleCreateSchema, req.body); const org = await requireOrganization(req); const id = crypto.randomUUID();
  await run(`INSERT INTO logistics_vehicles (id, organization_id, vehicle_type, total_quantity, available_quantity, capacity_category, starting_price_kobo, active, description) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`, id, org.id, body.vehicle_type, body.total_quantity, body.available_quantity, body.capacity_category, body.starting_price_kobo, body.active ? 1 : 0, body.description ?? null);
  res.status(201).json({ vehicle: await queryOne('SELECT * FROM logistics_vehicles WHERE id = ?', id) });
});
logisticsRouter.patch('/organization/vehicles/:id', requireRole('logistics_partner'), async (req, res) => {
  const body = parse(vehicleCreateSchema, req.body); const org = await requireOrganization(req);
  const existing = await queryOne('SELECT * FROM logistics_vehicles WHERE id = ? AND organization_id = ?', req.params.id, org.id);
  if (!existing) throw notFound('That vehicle does not exist.');
  const assigned = existing.total_quantity - existing.available_quantity;
  if (body.total_quantity < assigned) throw badRequest('Total quantity cannot be lower than vehicles currently assigned.');
  const available = body.available_quantity < 0 ? 0 : body.available_quantity;
  await run('UPDATE logistics_vehicles SET vehicle_type = ?, total_quantity = ?, available_quantity = ?, capacity_category = ?, starting_price_kobo = ?, active = ?, description = ?, updated_at = ? WHERE id = ?', body.vehicle_type, body.total_quantity, available, body.capacity_category, body.starting_price_kobo, body.active ? 1 : 0, body.description ?? null, new Date().toISOString(), existing.id);
  res.json({ vehicle: await queryOne('SELECT * FROM logistics_vehicles WHERE id = ?', existing.id) });
});

logisticsRouter.get('/organization/riders', requireRole('logistics_partner'), async (req, res) => {
  const org = await requireOrganization(req);
  const riderRows = await queryAll(`SELECT r.*, u.full_name, u.phone,
      (SELECT COUNT(*) FROM delivery_assignments a JOIN delivery_requests d ON d.id = a.delivery_request_id WHERE a.rider_id = r.id AND a.released_at IS NULL AND d.status IN ('assigned', 'picked_up', 'in_transit')) AS active_jobs
    FROM logistics_riders r JOIN users u ON u.id = r.user_id WHERE r.organization_id = ? ORDER BY u.full_name`, org.id);
  const riders = await Promise.all(riderRows
    .map(async (row) => ({ ...publicRider(row), activeJobs: row.active_jobs, modes: await queryAll('SELECT * FROM rider_delivery_modes WHERE rider_id = ? AND active = 1', row.id) })));
  res.json({ riders });
});

logisticsRouter.patch('/organization/riders', requireRole('logistics_partner'), async (req, res) => {
  const body = parse(riderAssignmentSchema, req.body); const org = await requireOrganization(req);
  const rider = await queryOne('SELECT * FROM logistics_riders WHERE user_id = ?', body.rider_user_id);
  if (!rider) throw notFound('That rider has not created a rider profile.');
  await run('UPDATE logistics_riders SET organization_id = ?, updated_at = ? WHERE id = ?', org.id, new Date().toISOString(), rider.id);
  res.json({ rider: publicRider(await riderForUser(body.rider_user_id)) });
});

// Rider profiles can operate independently or be assigned to an organization.
logisticsRouter.get('/rider', requireRole('rider'), async (req, res) => {
  const rider = await riderForUser(req.auth.userId);
  res.json({ rider: publicRider(rider), serviceAreas: rider ? await queryAll('SELECT * FROM rider_service_areas WHERE rider_id = ?', rider.id) : [], modes: rider ? await queryAll('SELECT * FROM rider_delivery_modes WHERE rider_id = ?', rider.id) : [] });
});
logisticsRouter.post('/rider', requireRole('rider'), async (req, res) => {
  if (await riderForUser(req.auth.userId)) throw conflict('This account already has a rider profile.', 'rider_exists');
  const body = parse(riderProfileSchema, req.body);
  const id = crypto.randomUUID();
  await run('INSERT INTO logistics_riders (id, user_id, phone, category, description) VALUES (?, ?, ?, ?, ?)', id, req.auth.userId, body.phone, body.category, body.description);
  res.status(201).json({ rider: publicRider(await riderForUser(req.auth.userId)) });
});

// Spec 6 — earnings mirror the business dashboard: a running total in kobo plus
// the history of every completed delivery that produced it.
const EARNINGS_SELECT = `
  SELECT d.id, t.transaction_number, b.business_name,
         o.name AS organization_name, u.full_name AS rider_name,
         COALESCE(d.accepted_price_kobo, d.published_price_kobo) AS amount_kobo,
         d.updated_at AS completed_at
    FROM delivery_requests d
    JOIN transactions t ON t.id = d.transaction_id
    JOIN businesses b ON b.id = d.business_id
    LEFT JOIN logistics_organizations o ON o.id = d.organization_id
    LEFT JOIN logistics_riders r
      ON r.id = COALESCE(d.rider_id, (SELECT a.rider_id FROM delivery_assignments a
          WHERE a.delivery_request_id = d.id AND a.rider_id IS NOT NULL
          ORDER BY a.released_at DESC LIMIT 1))
    LEFT JOIN users u ON u.id = r.user_id`;

function earningsBody(rows) {
  const history = rows.map((row) => ({
    id: row.id,
    transactionNumber: row.transaction_number,
    businessName: row.business_name,
    organizationName: row.organization_name,
    riderName: row.rider_name,
    amountKobo: row.amount_kobo ?? 0,
    completedAt: row.completed_at,
  }));
  const earningsKobo = history.reduce((sum, entry) => sum + entry.amountKobo, 0);
  return { earningsKobo, history };
}

logisticsRouter.get('/organization/earnings', requireRole('logistics_partner'), async (req, res) => {
  const org = await requireOrganization(req);
  const rows = await queryAll(
    `${EARNINGS_SELECT} WHERE d.organization_id = ? AND d.status = 'delivered' ORDER BY d.updated_at DESC`,
    org.id,
  );
  res.json(earningsBody(rows));
});

logisticsRouter.get('/rider/earnings', requireRole('rider'), async (req, res) => {
  const rider = await requireRider(req);
  const rows = await queryAll(
    `${EARNINGS_SELECT} WHERE d.status = 'delivered' AND (d.rider_id = ? OR d.id IN
      (SELECT delivery_request_id FROM delivery_assignments WHERE rider_id = ?))
     ORDER BY d.updated_at DESC`,
    rider.id,
    rider.id,
  );
  res.json(earningsBody(rows));
});
logisticsRouter.patch('/rider/availability', requireRole('rider'), async (req, res) => {
  const body = parse(availabilitySchema, req.body); const rider = await requireRider(req);
  const next = availabilityNext(rider, body);
  await run('UPDATE logistics_riders SET is_available = ?, availability_started_at = ?, availability_expires_at = ?, planned_hours = ?, updated_at = ? WHERE id = ?', next.is_available, next.started_at, next.expires_at, next.planned_hours, new Date().toISOString(), rider.id);
  res.json({ rider: publicRider(await riderForUser(req.auth.userId)) });
});
logisticsRouter.post('/rider/availability/extend', requireRole('rider'), async (req, res) => {
  const body = parse(availabilityAdjustSchema, req.body); const rider = await requireRider(req);
  if (!liveAvailability(rider)) throw badRequest('Become available before changing your closing time.');
  const next = adjustAvailability(rider, body.minutes);
  await run('UPDATE logistics_riders SET is_available = ?, availability_started_at = ?, availability_expires_at = ?, planned_hours = ?, updated_at = ? WHERE id = ?', next.is_available, next.started_at, next.expires_at, next.planned_hours, new Date().toISOString(), rider.id);
  res.json({ rider: publicRider(await riderForUser(req.auth.userId)) });
});
logisticsRouter.post('/rider/modes', requireRole('rider'), async (req, res) => {
  const body = parse(riderModeCreateSchema, req.body); const rider = await requireRider(req); const id = crypto.randomUUID();
  if (body.is_primary) await run('UPDATE rider_delivery_modes SET is_primary = 0 WHERE rider_id = ?', rider.id);
  await run('INSERT INTO rider_delivery_modes (id, rider_id, mode, capacity_category, rate_kobo, is_primary, active) VALUES (?, ?, ?, ?, ?, ?, ?)', id, rider.id, body.mode, body.capacity_category, body.rate_kobo, body.is_primary ? 1 : 0, body.active ? 1 : 0);
  res.status(201).json({ mode: await queryOne('SELECT * FROM rider_delivery_modes WHERE id = ?', id) });
});
logisticsRouter.post('/rider/areas', requireRole('rider'), async (req, res) => {
  const body = parse(serviceAreaSchema, req.body); const rider = await requireRider(req); const id = crypto.randomUUID();
  await run('INSERT INTO rider_service_areas (id, rider_id, city, area, state, country, latitude, longitude, radius_km) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', id, rider.id, body.city, body.area ?? null, body.state ?? null, body.country ?? null, body.latitude ?? null, body.longitude ?? null, body.radius_km ?? null);
  res.status(201).json({ serviceArea: await queryOne('SELECT * FROM rider_service_areas WHERE id = ?', id) });
});

// Spec 14/15 — matching is driven by the business pickup location and the
// customer destination, then by service-area coverage, suitability, price and
// distance. Anything that cannot serve the route is dropped before anything
// else is considered.
logisticsRouter.get('/providers', requireBusiness, async (req, res) => {
  const destinationCity = String(req.query.destination_city ?? '').trim();
  const packageSize = String(req.query.package_size ?? '').trim();
  const preferredMode = String(req.query.preferred_mode ?? '').trim();
  if (!destinationCity) throw badRequest('Provide destination_city to find suitable providers.');
  const pickup = await queryOne('SELECT * FROM business_locations WHERE business_id = ?', req.business.id);
  const pickupCity = String(pickup?.city ?? '').trim();
  const businessPoint = pickup && pickup.latitude != null && pickup.longitude != null
    ? { latitude: pickup.latitude, longitude: pickup.longitude }
    : null;

  const capacities = ['small', 'medium', 'large', 'very_large'];
  const supportsCapacity = (value) => !packageSize || capacities.indexOf(value) >= capacities.indexOf(packageSize);

  // Distance from the business to the nearest covered point, so the owner's own
  // location influences ordering rather than just the destination name.
  const distanceFor = (rows) => {
    if (!businessPoint) return null;
    const points = rows.filter((row) => row.latitude != null && row.longitude != null);
    if (points.length === 0) return null;
    return Math.round(Math.min(...points.map((row) => haversineKm(businessPoint, row))));
  };

  const coversCity = (rows, city) => !city || rows.some((row) => String(row.city).toLowerCase() === city.toLowerCase());

  // Spec 15 — order by how close the match is to the business: same state
  // first, then same town, then straight-line distance. Ties keep insertion
  // order, so the list is stable across refreshes.
  const normalise = (value) => String(value ?? '').trim().toLowerCase();
  const pickupState = normalise(pickup?.state);
  const rankBy = (a, b) => {
    const tier = (entry) => [
      pickupState && entry.serviceAreas.some((area) => normalise(area.state) === pickupState) ? 0 : 1,
      pickupCity && entry.serviceAreas.some((area) => normalise(area.city) === normalise(pickupCity)) ? 0 : 1,
      entry.distanceKm == null ? Number.MAX_SAFE_INTEGER : entry.distanceKm,
    ];
    const left = tier(a);
    const right = tier(b);
    for (let index = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) return left[index] - right[index];
    }
    return 0;
  };

  const providerRows = await queryAll(`SELECT DISTINCT o.* FROM logistics_organizations o
    JOIN logistics_service_areas a ON a.organization_id = o.id
    WHERE o.is_available = 1 AND (o.availability_expires_at IS NULL OR o.availability_expires_at > ?)
      AND lower(a.city) = lower(?)`, new Date().toISOString(), destinationCity);

  const providers = (await Promise.all(providerRows
    .map(async (org) => ({ ...(await organizationDetails(org)), organization: publicOrganization(org) }))))
    .map((provider) => ({ ...provider, distanceKm: distanceFor(provider.serviceAreas) }))
    .map((provider) => ({ ...provider, vehicles: provider.vehicles.filter((vehicle) => vehicle.isActive && vehicle.availableQuantity > 0 && supportsCapacity(vehicle.capacity_category) && (!preferredMode || vehicle.vehicle_type === preferredMode)) }))
    // A provider that cannot pick up from the business cannot serve the route.
    .filter((provider) => provider.vehicles.length > 0 && coversCity(provider.serviceAreas, pickupCity))
    .map((provider) => ({ ...provider, serviceAreas: provider.serviceAreas.map(publicServiceArea) }))
    .sort(rankBy);

  const riderRows = await queryAll(`SELECT DISTINCT r.*, u.full_name, u.phone FROM logistics_riders r
    JOIN users u ON u.id = r.user_id
    JOIN rider_service_areas a ON a.rider_id = r.id
    WHERE r.is_available = 1 AND (r.availability_expires_at IS NULL OR r.availability_expires_at > ?)
      AND lower(a.city) = lower(?)`, new Date().toISOString(), destinationCity);

  const riderEntries = await Promise.all(riderRows
    .map(async (row) => {
      const areas = await queryAll('SELECT * FROM rider_service_areas WHERE rider_id = ?', row.id);
      return { row, areas };
    }));

  const riders = (await Promise.all(riderEntries
    .map(async (entry) => ({
      rider: publicRider(entry.row),
      modes: (await queryAll('SELECT * FROM rider_delivery_modes WHERE rider_id = ? AND active = 1', entry.row.id))
        .filter((mode) => supportsCapacity(mode.capacity_category) && (!preferredMode || mode.mode === preferredMode)),
      serviceAreas: entry.areas.map(publicServiceArea),
      distanceKm: distanceFor(entry.areas),
    }))))
    .filter((entry) => entry.modes.length > 0 && coversCity(entry.serviceAreas, pickupCity))
    .sort(rankBy);

  res.json({ providers, riders });
});

function publicServiceArea(row) {
  return {
    id: row.id, city: row.city, area: row.area, state: row.state, country: row.country,
    latitude: row.latitude, longitude: row.longitude, radiusKm: row.radius_km,
  };
}

function haversineKm(from, to) {
  const toRadians = (degrees) => (degrees * Math.PI) / 180;
  const earthKm = 6371;
  const dLat = toRadians(to.latitude - from.latitude);
  const dLng = toRadians(to.longitude - from.longitude);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRadians(from.latitude)) * Math.cos(toRadians(to.latitude)) * Math.sin(dLng / 2) ** 2;
  return earthKm * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

logisticsRouter.post('/requests', requireBusiness, async (req, res) => {
  const body = parse(deliveryRequestSchema, req.body); const business = req.business;
  const sale = await queryOne('SELECT * FROM transactions WHERE id = ? AND business_id = ?', body.transaction_id, business.id);
  if (!sale) throw notFound('That transaction does not exist.');
  if (!sale.delivery_required || !sale.delivery_address) throw badRequest('This transaction does not require delivery.');
  if (await queryOne('SELECT id FROM delivery_requests WHERE transaction_id = ?', sale.id)) throw conflict('This transaction already has a delivery request.', 'delivery_request_exists');
  const pickup = await queryOne('SELECT * FROM business_locations WHERE business_id = ?', business.id);
  if (!pickup) throw badRequest('Add your business location before requesting delivery.');
  // Pricing rows and service areas are published per destination (spec 20), so
  // the city is derived once and used for coverage, pricing and the record.
  const destinationCity = String(sale.delivery_address).split(',').pop().trim();
  let publishedPrice = null;
  if (body.organization_id) {
    const org = await queryOne('SELECT * FROM logistics_organizations WHERE id = ?', body.organization_id);
    if (!org || !liveAvailability(org)) throw badRequest('That logistics organization is not currently available.');
    if (!(await queryOne('SELECT id FROM logistics_service_areas WHERE organization_id = ? AND lower(city) = lower(?)', org.id, destinationCity))) throw badRequest('That organization does not serve this destination.');
    const vehicle = await queryOne(`SELECT id FROM logistics_vehicles WHERE organization_id = ? AND active = 1 AND available_quantity > 0
      ${body.preferred_mode ? 'AND vehicle_type = ?' : ''}`, ...(body.preferred_mode ? [org.id, body.preferred_mode] : [org.id]));
    if (!vehicle) throw badRequest('That organization has no suitable available vehicle.');
    publishedPrice = (await queryOne('SELECT price_kobo FROM logistics_pricing WHERE organization_id = ? AND lower(destination) = lower(?) ORDER BY price_kobo LIMIT 1', org.id, destinationCity))?.price_kobo ?? null;
  } else {
    const rider = await queryOne('SELECT * FROM logistics_riders WHERE id = ?', body.rider_id);
    if (!rider || !liveAvailability(rider)) throw badRequest('That rider is not currently available.');
  }
  const id = crypto.randomUUID();
  await run(`INSERT INTO delivery_requests (id, transaction_id, business_id, organization_id, rider_id, pickup_address, pickup_city, destination_address, destination_city, package_description, package_size, preferred_mode, published_price_kobo) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, id, sale.id, business.id, body.organization_id ?? null, body.rider_id ?? null, pickup.address, pickup.city ?? null, sale.delivery_address, destinationCity, body.package_description ?? null, body.package_size ?? null, body.preferred_mode ?? null, publishedPrice);
  const created = await requestRow(id); const recipients = await requestRecipients(created);
  await event(id, req.auth.userId, 'requested');
  await notify(recipients.organizationOwner ?? recipients.riderUser, id, 'delivery_requested', 'New delivery request', `${created.business_name} requested delivery to ${created.destination_city ?? created.destination_address}.`);
  res.status(201).json({ deliveryRequest: publicRequest(created) });
});

// Spec 28/53 — one delivery, broken down: where it starts, where it goes, who
// ordered it, who receives it and who carries it, with names and phone numbers
// so nobody has to leave the app to start calling people. The pickup side
// carries the business exactly as its owner typed it — name, contact number
// and the location (city, area, state) — because the partner and the rider
// call the shop before they call anyone else.
logisticsRouter.get('/requests/:id', async (req, res) => {
  const request = await requestRow(req.params.id);
  const recipients = await requestRecipients(request);
  const allowed = [recipients.businessOwner, recipients.organizationOwner, recipients.riderUser];
  if (!allowed.includes(req.auth.userId)) throw notFound('That delivery request does not exist.');

  const sale = await queryOne('SELECT * FROM transactions WHERE id = ?', request.transaction_id);
  const business = await queryOne('SELECT * FROM businesses WHERE id = ?', request.business_id);
  const businessOwner = business ? await queryOne('SELECT full_name, phone, email FROM users WHERE id = ?', business.owner_user_id) : null;
  const customer = sale?.customer_id ? await queryOne('SELECT * FROM customers WHERE id = ?', sale.customer_id) : null;
  // Spec 40 — a rider reaches the job either directly (rider_id) or through an
  // assignment row, and both have to resolve to the person carrying it.
  const riderId = request.rider_id
    ?? (await queryOne('SELECT rider_id FROM delivery_assignments WHERE delivery_request_id = ? AND released_at IS NULL AND rider_id IS NOT NULL', request.id))?.rider_id
    ?? null;
  const rider = riderId
    ? await queryOne('SELECT r.*, u.full_name, u.phone FROM logistics_riders r JOIN users u ON u.id = r.user_id WHERE r.id = ?', riderId)
    : null;
  const organization = request.organization_id ? await queryOne('SELECT * FROM logistics_organizations WHERE id = ?', request.organization_id) : null;
  const pickup = await queryOne('SELECT * FROM business_locations WHERE business_id = ?', request.business_id);

  res.json({
    deliveryRequest: {
      ...publicRequest(request),
      riderId: rider?.id ?? null,
      pickup: pickup
        ? { address: pickup.address, city: pickup.city, area: pickup.area, state: pickup.state, country: pickup.country, latitude: pickup.latitude, longitude: pickup.longitude }
        : null,
      destination: { address: request.destination_address, city: request.destination_city },
      business: business
        ? { name: business.business_name, ownerName: businessOwner?.full_name ?? null, phone: business.phone ?? businessOwner?.phone ?? null, email: business.email ?? businessOwner?.email ?? null }
        : null,
      customer: customer ? { name: customer.name, phone: customer.phone, email: customer.email } : null,
      rider: rider ? { name: rider.full_name, phone: rider.phone } : null,
      organization: organization ? { name: organization.name, phone: organization.phone, email: organization.email } : null,
      totals: sale
        ? { subtotalKobo: sale.subtotal_kobo, discountKobo: sale.discount_kobo, deliveryFeeKobo: sale.delivery_fee_kobo, totalKobo: sale.total_kobo }
        : null,
      events: (await queryAll('SELECT e.*, u.full_name FROM delivery_request_events e JOIN users u ON u.id = e.actor_user_id WHERE e.delivery_request_id = ? ORDER BY e.created_at', request.id))
        .map((row) => ({ id: row.id, eventType: row.event_type, note: row.note, actorName: row.full_name, createdAt: row.created_at })),
    },
  });
});

logisticsRouter.get('/requests/:id/events', async (req, res) => {
  const request = await requestRow(req.params.id); const recipients = await requestRecipients(request);
  if (![recipients.businessOwner, recipients.organizationOwner, recipients.riderUser].includes(req.auth.userId)) throw notFound('That delivery request does not exist.');
  res.json({ events: (await queryAll('SELECT e.*, u.full_name FROM delivery_request_events e JOIN users u ON u.id = e.actor_user_id WHERE e.delivery_request_id = ? ORDER BY e.created_at', request.id)).map((row) => ({ id: row.id, eventType: row.event_type, note: row.note, actorName: row.full_name, createdAt: row.created_at })) });
});

logisticsRouter.get('/requests', async (req, res) => {
  let where; let value;
  if (req.auth.role === 'business') { const business = await findBusinessForUser(req.auth.userId); if (!business) return res.json({ deliveryRequests: [] }); where = 'd.business_id = ?'; value = business.id; }
  else if (req.auth.role === 'logistics_partner') { const org = await organizationForUser(req.auth.userId); if (!org) return res.json({ deliveryRequests: [] }); where = 'd.organization_id = ?'; value = org.id; }
  else { const rider = await riderForUser(req.auth.userId); if (!rider) return res.json({ deliveryRequests: [] }); where = 'd.rider_id = ? OR d.id IN (SELECT delivery_request_id FROM delivery_assignments WHERE rider_id = ? AND released_at IS NULL)'; value = rider.id; const rows = await queryAll(`SELECT d.*, t.transaction_number, b.business_name, o.name AS organization_name, u.full_name AS rider_name FROM delivery_requests d JOIN transactions t ON t.id=d.transaction_id JOIN businesses b ON b.id=d.business_id LEFT JOIN logistics_organizations o ON o.id=d.organization_id LEFT JOIN logistics_riders r ON r.id=COALESCE(d.rider_id, (SELECT a.rider_id FROM delivery_assignments a WHERE a.delivery_request_id=d.id AND a.released_at IS NULL AND a.rider_id IS NOT NULL)) LEFT JOIN users u ON u.id=r.user_id WHERE ${where} ORDER BY d.created_at DESC`, value, value); return res.json({ deliveryRequests: rows.map(publicRequest) }); }
  const rows = await queryAll(`SELECT d.*, t.transaction_number, b.business_name, o.name AS organization_name, u.full_name AS rider_name FROM delivery_requests d JOIN transactions t ON t.id=d.transaction_id JOIN businesses b ON b.id=d.business_id LEFT JOIN logistics_organizations o ON o.id=d.organization_id LEFT JOIN logistics_riders r ON r.id=COALESCE(d.rider_id, (SELECT a.rider_id FROM delivery_assignments a WHERE a.delivery_request_id=d.id AND a.released_at IS NULL AND a.rider_id IS NOT NULL)) LEFT JOIN users u ON u.id=r.user_id WHERE ${where} ORDER BY d.created_at DESC`, value);
  res.json({ deliveryRequests: rows.map(publicRequest) });
});

logisticsRouter.patch('/requests/:id/quote', requireRole('logistics_partner'), async (req, res) => {
  const body = parse(quoteSchema, req.body); const org = await requireOrganization(req); const request = await requestRow(req.params.id);
  if (request.organization_id !== org.id) throw notFound('That delivery request does not exist.');
  if (!['requested', 'quoted'].includes(request.status)) throw badRequest('This request can no longer be quoted.');
  await run('UPDATE delivery_requests SET quoted_price_kobo = ?, status = \'quoted\', updated_at = ? WHERE id = ?', body.quoted_price_kobo, new Date().toISOString(), request.id);
  await event(request.id, req.auth.userId, 'quoted'); await notify((await requestRecipients(request)).businessOwner, request.id, 'quote_received', 'Delivery quote received', 'A provider sent a delivery quote.');
  res.json({ deliveryRequest: publicRequest(await requestRow(request.id)) });
});

logisticsRouter.patch('/requests/:id/accept-quote', requireBusiness, async (req, res) => {
  const request = await requestForBusiness(req.params.id, req.business.id);
  if (request.status !== 'quoted') throw badRequest('There is no active quote to accept.');
  await transaction(async () => { await run('UPDATE delivery_requests SET accepted_price_kobo = quoted_price_kobo, status = \'accepted\', updated_at = ? WHERE id = ?', new Date().toISOString(), request.id); await updateTransactionDelivery(request.transaction_id, 'accepted', req.auth.userId); await event(request.id, req.auth.userId, 'quote_accepted'); });
  await notify((await requestRecipients(request)).organizationOwner, request.id, 'quote_accepted', 'Quote accepted', 'The business accepted your delivery quote.');
  res.json({ deliveryRequest: publicRequest(await requestRow(request.id)) });
});

logisticsRouter.patch('/requests/:id/assign', requireRole('logistics_partner'), async (req, res) => {
  const body = parse(assignmentSchema, req.body); const org = await requireOrganization(req); const request = await requestRow(req.params.id);
  if (request.organization_id !== org.id) throw notFound('That delivery request does not exist.');
  // Re-assignment has to stay possible on an already-open request (spec 40):
  // `assigned` is the state a previous assignment left behind, not a closed one.
  if (!['accepted', 'requested', 'assigned'].includes(request.status)) throw badRequest('This request cannot be assigned now.');
  if (body.rider_id) { const rider = await queryOne('SELECT * FROM logistics_riders WHERE id = ? AND organization_id = ?', body.rider_id, org.id); if (!rider) throw badRequest('Choose one of your organization riders.'); }
  if (body.vehicle_id) { const vehicle = await queryOne('SELECT * FROM logistics_vehicles WHERE id = ? AND organization_id = ? AND active = 1 AND available_quantity > 0', body.vehicle_id, org.id); if (!vehicle) throw badRequest('Choose an available active vehicle.'); }
  await transaction(async () => {
    // Re-assigning an open request must not strand the vehicle the previous
    // assignment was holding, so the old one is given back before this one is
    // taken out of the pool.
    await releaseRequestVehicles(request.id, req.auth.userId);
    await run('INSERT INTO delivery_assignments (id, delivery_request_id, rider_id, vehicle_id, assigned_by_user_id) VALUES (?, ?, ?, ?, ?) ON CONFLICT (delivery_request_id) DO UPDATE SET rider_id = EXCLUDED.rider_id, vehicle_id = EXCLUDED.vehicle_id, assigned_by_user_id = EXCLUDED.assigned_by_user_id, assigned_at = now_iso(), released_at = NULL', crypto.randomUUID(), request.id, body.rider_id ?? null, body.vehicle_id ?? null, req.auth.userId);
    if (body.vehicle_id) await run('UPDATE logistics_vehicles SET available_quantity = available_quantity - 1, updated_at = ? WHERE id = ?', new Date().toISOString(), body.vehicle_id);
    await run('UPDATE delivery_requests SET status = \'assigned\', updated_at = ? WHERE id = ?', new Date().toISOString(), request.id);
    // Assignment means the provider took the work, so the transaction's delivery
    // axis has to leave `pending` here. Without it the next legal step,
    // `picked_up`, is refused by the status graph even though the request
    // itself is already assigned (spec 29: Requested -> Accepted -> Assigned).
    await updateTransactionDelivery(request.transaction_id, 'accepted', req.auth.userId);
    await event(request.id, req.auth.userId, 'assigned');
  });
  const assignedRider = body.rider_id ? (await queryOne('SELECT user_id FROM logistics_riders WHERE id = ?', body.rider_id))?.user_id : null;
  await notify(assignedRider, request.id, 'delivery_assigned', 'New delivery assignment', 'You have been assigned a delivery.');
  await notify((await requestRecipients(request)).businessOwner, request.id, 'rider_assigned', 'Delivery assigned', 'A rider has been assigned to your delivery.');
  res.json({ deliveryRequest: publicRequest(await requestRow(request.id)) });
});

logisticsRouter.patch('/requests/:id/status', requireRole('logistics_partner', 'rider'), async (req, res) => {
  const body = parse(deliveryUpdateSchema, req.body); const request = await requestRow(req.params.id);
  if (req.auth.role === 'logistics_partner' && request.organization_id !== (await requireOrganization(req)).id) throw notFound('That delivery request does not exist.');
  if (req.auth.role === 'rider') { const rider = await requireRider(req); const assignment = await queryOne('SELECT id FROM delivery_assignments WHERE delivery_request_id = ? AND rider_id = ? AND released_at IS NULL', request.id, rider.id); if (request.rider_id !== rider.id && !assignment) throw notFound('That delivery request does not exist.'); }
  const allowed = { requested: ['accepted', 'declined'], quoted: ['accepted', 'declined'], accepted: ['picked_up'], assigned: ['picked_up'], picked_up: ['in_transit'], in_transit: ['delivered', 'failed'] };
  if (!(allowed[request.status] ?? []).includes(body.status)) throw badRequest('That delivery status change is not allowed.');
  await transaction(async () => {
    await run('UPDATE delivery_requests SET status = ?, failure_reason = ?, updated_at = ? WHERE id = ?', body.status, body.failure_reason ?? null, new Date().toISOString(), request.id);
    if (['accepted', 'picked_up', 'in_transit'].includes(body.status)) await updateTransactionDelivery(request.transaction_id, body.status, req.auth.userId);
    if (body.status === 'failed') await updateTransactionDelivery(request.transaction_id, 'failed', req.auth.userId);
    // A delivery that ends at delivered, failed or declined is over, so the
    // fleet it was holding has to go back into the pool.
    if (['delivered', 'failed', 'declined', 'cancelled'].includes(body.status)) await releaseRequestVehicles(request.id, req.auth.userId);
    await event(request.id, req.auth.userId, body.status, body.failure_reason ?? null);
  });
  const recipients = await requestRecipients(request); await notify(recipients.businessOwner, request.id, `delivery_${body.status}`, `Delivery ${body.status.replace('_', ' ')}`, body.failure_reason ?? 'Your delivery status was updated.');
  res.json({ deliveryRequest: publicRequest(await requestRow(request.id)) });
});

logisticsRouter.post('/requests/:id/otp', async (req, res) => {
  const body = parse(deliveryOtpSchema, req.body); const request = await requestRow(req.params.id); const recipients = await requestRecipients(request);
  if (![recipients.businessOwner, recipients.organizationOwner, recipients.riderUser].includes(req.auth.userId)) throw notFound('That delivery request does not exist.');
  if (!['assigned', 'picked_up', 'in_transit', 'delivered'].includes(request.status)) throw badRequest('An OTP can be created after a delivery is assigned.');
  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
  const expires = new Date(Date.now() + body.expires_in_minutes * 60_000).toISOString();
  await run('INSERT INTO delivery_confirmation_otps (id, delivery_request_id, code_hash, expires_at, verified_at) VALUES (?, ?, ?, ?, NULL) ON CONFLICT (delivery_request_id) DO UPDATE SET code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at, verified_at = NULL, created_at = now_iso()', crypto.randomUUID(), request.id, crypto.createHash('sha256').update(code).digest('hex'), expires);
  await event(request.id, req.auth.userId, 'otp_created');
  // A real notification provider is deliberately inactive. The development
  // response is the explicit test seam until customer messaging is implemented.
  res.status(201).json({ expiresAt: expires, ...(config.isProd ? {} : { developmentOtp: code }) });
});

logisticsRouter.post('/requests/:id/retry', requireBusiness, async (req, res) => {
  const request = await requestForBusiness(req.params.id, req.business.id);
  if (!['failed', 'declined', 'cancelled'].includes(request.status)) throw badRequest('Only a failed, declined, or cancelled delivery can be retried.');
  await transaction(async () => {
    await releaseRequestVehicles(request.id, req.auth.userId);
    await run('UPDATE delivery_requests SET status = \'requested\', failure_reason = NULL, quoted_price_kobo = NULL, accepted_price_kobo = NULL, updated_at = ? WHERE id = ?', new Date().toISOString(), request.id);
    await updateTransactionDelivery(request.transaction_id, 'pending', req.auth.userId);
    await event(request.id, req.auth.userId, 'retried');
  });
  res.json({ deliveryRequest: publicRequest(await requestRow(request.id)) });
});

logisticsRouter.post('/requests/:id/confirm', async (req, res) => {
  const body = parse(confirmationSchema, req.body); const request = await requestRow(req.params.id);
  const business = req.auth.role === 'business' ? await findBusinessForUser(req.auth.userId) : null;
  const allowedProvider = req.auth.role === 'logistics_partner' && request.organization_id === (await organizationForUser(req.auth.userId))?.id;
  const allowedRider = req.auth.role === 'rider' && (request.rider_id === (await riderForUser(req.auth.userId))?.id || await queryOne('SELECT id FROM delivery_assignments WHERE delivery_request_id = ? AND rider_id = ?', request.id, (await riderForUser(req.auth.userId))?.id));
  if (!(business?.id === request.business_id || allowedProvider || allowedRider)) throw forbidden('You cannot confirm this delivery.');
  if (request.status !== 'delivered') throw badRequest('Mark the delivery delivered before confirming it.');
  if (body.method === 'otp') {
    const otp = await queryOne('SELECT * FROM delivery_confirmation_otps WHERE delivery_request_id = ?', request.id);
    const supplied = crypto.createHash('sha256').update(body.otp).digest('hex');
    if (!otp || otp.verified_at || otp.expires_at <= new Date().toISOString() || supplied !== otp.code_hash) throw badRequest('That customer OTP is invalid or has expired.');
    await run('UPDATE delivery_confirmation_otps SET verified_at = ? WHERE id = ?', new Date().toISOString(), otp.id);
  }
  await transaction(async () => { await run('INSERT INTO delivery_confirmations (id, delivery_request_id, confirmed_by_user_id, method, proof_note) VALUES (?, ?, ?, ?, ?)', crypto.randomUUID(), request.id, req.auth.userId, body.method, body.proof_note ?? null); await updateTransactionDelivery(request.transaction_id, 'delivered', req.auth.userId); await event(request.id, req.auth.userId, 'confirmed', body.method); });
  const recipients = await requestRecipients(request); await notify(recipients.businessOwner, request.id, 'delivery_confirmed', 'Delivery confirmed', 'The customer delivery was confirmed.');
  res.status(201).json({ deliveryRequest: publicRequest(await requestRow(request.id)) });
});
