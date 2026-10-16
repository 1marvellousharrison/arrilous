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

// A write that needs the owner to have passed the business-edit OTP gate. The
// app keys off `code` to re-run the gate instead of showing a dead end.
export const editVerificationRequired = (
  message = 'Confirm it is you before changing your business details.'
) => new ApiError(403, 'business_edit_verification_required', message);

export const serviceUnavailable = (
  message = 'That service is unavailable right now. Please try again later.'
) => new ApiError(503, 'service_unavailable', message);

export const notFound = (message = 'Resource not found.') =>
  new ApiError(404, 'not_found', message);

export const conflict = (message, code = 'conflict') => new ApiError(409, code, message);

export const tooManyRequests = (message, retryAfterSeconds) =>
  new ApiError(429, 'too_many_requests', message, retryAfterSeconds ? { retryAfterSeconds } : undefined);

export const serverError = () =>
  new ApiError(500, 'server_error', 'Something went wrong on our side. Please try again.');
