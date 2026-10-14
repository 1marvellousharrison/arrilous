import { queryOne } from '../db/index.js';
import { notFound, forbidden } from '../lib/errors.js';

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
 * requireAuth + a business. Responds 404 (not 403) when the owner simply has no
 * business yet, because "finish setting up" is a next step for that user, not
 * an authorisation failure. A non-business role gets 403, since a logistics
 * partner or rider never owns a business.
 */
export async function requireBusiness(req, _res, next) {
  try {
    if (req.auth.role !== 'business') {
      throw forbidden('This area is only available to business accounts.');
    }
    const business = await findBusinessForUser(req.auth.userId);
    if (!business) {
      throw notFound('Finish setting up your business first.');
    }
    req.business = business;
    return next();
  } catch (error) {
    return next(error);
  }
}
