import { ApiError } from '../lib/errors.js';
import { config } from '../config.js';

export function notFoundHandler(req, _res, next) {
  next(new ApiError(404, 'not_found', `No route for ${req.method} ${req.path}`));
}

// eslint-disable-next-line no-unused-vars -- Express identifies error handlers by arity.
export function errorHandler(error, req, res, _next) {
  if (error instanceof ApiError) {
    return res.status(error.status).json({
      error: {
        code: error.code,
        message: error.message,
        ...(error.details ? { details: error.details } : {}),
      },
    });
  }

  if (error?.type === 'entity.parse.failed') {
    return res.status(400).json({
      error: { code: 'invalid_json', message: 'Request body is not valid JSON.' },
    });
  }

  if (!config.isProd) {
    console.error(`[error] ${req.method} ${req.path}`, error);
  }
  return res.status(500).json({
    error: { code: 'server_error', message: 'Something went wrong on our side. Please try again.' },
  });
}
