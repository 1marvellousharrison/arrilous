import { forbidden } from '../lib/errors.js';

export function requireRole(...roles) {
  return (req, _res, next) => {
    if (!roles.includes(req.auth.role)) {
      return next(forbidden('This account does not have permission for that logistics action.'));
    }
    return next();
  };
}
