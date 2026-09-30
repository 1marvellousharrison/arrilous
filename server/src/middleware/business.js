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
export function findBusinessForUser(userId) {
  return queryOne('SELECT * FROM businesses WHERE owner_user_id = ?', userId);
}

/**
 * requireAuth + a business. Responds 404 (not 403) when the owner simply has no
 * business yet, because "finish setting up" is a next step for that user, not
 * an authorisation failure. A non-business role gets 403, since a logistics
 * partner or rider never owns a business.
 */
export function requireBusiness(req, _res, next) {
  try {
    if (req.auth.role !== 'business') {
      throw forbidden('This area is only available to business accounts.');
    }
    const business = findBusinessForUser(req.auth.userId);
    if (!business) {
      throw notFound('Finish setting up your business first.');
    }
    req.business = business;
    return next();
  } catch (error) {
    return next(error);
  }
}
