/**
 * Every failure leaving the API uses this envelope:
 *   { "error": { "code": "machine_readable_code", "message": "human text", "details"?: [...] } }
 */
export class ApiError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    if (details) this.details = details;
  }
}

export const badRequest = (message, details) =>
  new ApiError(400, 'bad_request', message, details);

export const validationFailed = (details) =>
  new ApiError(422, 'validation_failed', 'Some fields need your attention.', details);

export const unauthorized = (message = 'You need to sign in to continue.') =>
  new ApiError(401, 'unauthorized', message);

export const forbidden = (message = 'You do not have access to this resource.') =>
  new ApiError(403, 'forbidden', message);

export const notFound = (message = 'Resource not found.') =>
  new ApiError(404, 'not_found', message);

export const conflict = (message, code = 'conflict') => new ApiError(409, code, message);

export const tooManyRequests = (message, retryAfterSeconds) =>
  new ApiError(429, 'too_many_requests', message, retryAfterSeconds ? { retryAfterSeconds } : undefined);

export const serverError = () =>
  new ApiError(500, 'server_error', 'Something went wrong on our side. Please try again.');
