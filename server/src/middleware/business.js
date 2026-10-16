import { queryOne } from '../db/index.js';
import { notFound, forbidden, editVerificationRequired } from '../lib/errors.js';
import { verifyBusinessEditToken } from '../lib/jwt.js';

/**
 * Resolves the business that owns the request from the access token.
 *
 * This is the single isolation choke point for Phases 1-7: routes read
 * business_id from req.business and never from the request body, so swapping an
 * id in a payload cannot reach another business's rows.
 *
 * One business per owner is enforced by a UNIQUE constraint on owner_user_id, so
 * this is a single lookup with no ambiguity.
 */
export async function findBusinessForUser(userId) {
  return queryOne('SELECT * FROM businesses WHERE owner_user_id = ?', userId);
}

/**
 * Resolves a staff login to the business it serves, via the link table.
 *
 * A staff is never the owner, so this is the only correct lookup for their
 * business: owner_user_id would return nothing. Returns the link row and the
 * business together so requireBusiness can publish both.
 */
export async function findStaffContextForUser(userId) {
  const staff = await queryOne('SELECT * FROM staff_members WHERE user_id = ?', userId);
  if (!staff) return null;
  const business = await queryOne('SELECT * FROM businesses WHERE id = ?', staff.business_id);
  if (!business) return null;
  return { staff, business };
}

/**
 * Role check only, for the routes that create a business.
 *
 * requireBusiness would also demand an existing business, which is impossible on
 * the route that creates one. Without this, a rider could sign up, POST /business
 * and become an owner of a store — the client UI hides that path, but the API
 * must not depend on the client hiding it.
 */
export function requireBusinessOwner(req, _res, next) {
  try {
    if (req.auth.role !== 'business') {
      throw forbidden('Only a business account can own a business.');
    }
    return next();
  } catch (error) {
    return next(error);
  }
}

/**
 * requireAuth + a business, for either the owner or a staff member.
 *
 * Responds 404 (not 403) when an owner simply has no business yet, because
 * "finish setting up" is a next step for that user, not an authorisation
 * failure. A logistics partner or rider gets 403, since neither ever belongs to
 * a business.
 *
 * A staff resolves its business through staff_members, and only while the link
 * is active — a disabled (or not-yet-activated) staff is refused here even if
 * their access token is still unexpired. req.staff is set to the link row for a
 * staff and null for the owner, which is how downstream routes tell them apart.
 */
export async function requireBusiness(req, _res, next) {
  try {
    if (req.auth.role === 'business') {
      const business = await findBusinessForUser(req.auth.userId);
      if (!business) {
        throw notFound('Finish setting up your business first.');
      }
      req.business = business;
      req.staff = null;
      return next();
    }

    if (req.auth.role === 'staff') {
      const context = await findStaffContextForUser(req.auth.userId);
      if (!context || context.staff.status !== 'active') {
        throw forbidden('This staff account is not active.');
      }
      req.business = context.business;
      req.staff = context.staff;
      return next();
    }

    throw forbidden('This area is only available to business accounts.');
  } catch (error) {
    return next(error);
  }
}

/**
 * Owner-only gate for the writes a staff must never make (adding products,
 * editing customers, changing business details, managing staff, moving a sale's
 * status). Assumes requireBusiness has already resolved req.business.
 */
export function requireOwner(req, _res, next) {
  try {
    if (req.auth.role !== 'business') {
      throw forbidden('Only the business owner can do this.');
    }
    return next();
  } catch (error) {
    return next(error);
  }
}

/**
 * Owner-confirmation gate for editing an existing business profile.
 *
 * Assumes requireBusiness + requireOwner have already resolved req.business, and
 * demands a short-lived `x-business-edit-token` minted after the owner passed
 * the email OTP. The subject must be the business's owner, so a token for one
 * business cannot unlock another.
 *
 * `onlyWhenPresent` exempts the first write: a business that has no location
 * yet is still being set up, not edited, so its very first location write is
 * allowed through. Every later write is a change and needs the token. See
 * docs/business-details-edit-otp.md.
 */
export function requireBusinessEditToken({ onlyWhenPresent = false } = {}) {
  return async function businessEditGate(req, _res, next) {
    try {
      if (onlyWhenPresent) {
        const existing = await queryOne(
          'SELECT id FROM business_locations WHERE business_id = ?',
          req.business.id
        );
        if (!existing) return next();
      }

      const claims = verifyBusinessEditToken(req.get('x-business-edit-token'));
      if (!claims || claims.sub !== req.business.owner_user_id) {
        throw editVerificationRequired();
      }
      return next();
    } catch (error) {
      return next(error);
    }
  };
}
