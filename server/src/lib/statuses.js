import { badRequest } from './errors.js';

/**
 * Phase 7 — four independent status axes.
 *
 * A transaction is described by four separate columns rather than one "status",
 * because "confirmed + paid + awaiting delivery + open" is a normal state that a
 * single column cannot represent without lying about three of them.
 */
export const ORDER_STATUSES = ['pending', 'confirmed', 'cancelled'];
export const PAYMENT_STATUSES = ['unpaid', 'payment_pending', 'paid', 'failed', 'refunded'];
export const DELIVERY_STATUSES = [
  'not_required',
  'pending',
  'accepted',
  'picked_up',
  'in_transit',
  'delivered',
  'failed',
];
export const COMPLETION_STATUSES = ['open', 'completed'];

export const STATUS_TYPES = {
  order: {
    label: 'order',
    values: ORDER_STATUSES,
    transitions: {
      pending: ['confirmed', 'cancelled'],
      confirmed: ['cancelled'],
      cancelled: [],
    },
  },
  payment: {
    label: 'payment',
    values: PAYMENT_STATUSES,
    transitions: {
      unpaid: ['payment_pending', 'paid', 'failed'],
      payment_pending: ['paid', 'failed'],
      paid: ['refunded'],
      failed: ['payment_pending', 'paid'],
      refunded: [],
    },
  },
  delivery: {
    label: 'delivery',
    values: DELIVERY_STATUSES,
    transitions: {
      not_required: ['pending'],
      pending: ['accepted', 'failed'],
      accepted: ['picked_up', 'failed'],
      picked_up: ['in_transit', 'failed'],
      in_transit: ['delivered', 'failed'],
      delivered: [],
      failed: ['pending'],
    },
  },
  completion: {
    label: 'completion',
    values: COMPLETION_STATUSES,
    transitions: {
      open: ['completed'],
      completed: [],
    },
  },
};

/** Delivery states that mean "this order still has to reach the customer". */
export const DELIVERY_IN_FLIGHT = ['pending', 'accepted', 'picked_up', 'in_transit'];

export function assertStatusType(type) {
  if (!STATUS_TYPES[type]) throw badRequest(`Unknown status type "${type}".`);
  return STATUS_TYPES[type];
}

/**
 * Rejects a status change that the transition table does not allow.
 *
 * Phase 15 expands on this with the full rule set; the table is in place now so
 * a completed transaction can never silently revert, which is a correctness
 * requirement rather than a later-phase nicety.
 */
export function assertTransition(type, from, to) {
  const definition = assertStatusType(type);
  if (!definition.values.includes(to)) {
    throw badRequest(
      `"${to}" is not a valid ${definition.label} status.`,
      [{ field: type, message: `Use one of: ${definition.values.join(', ')}.` }]
    );
  }
  if (from === to) return;
  const allowed = definition.transitions[from] ?? [];
  if (!allowed.includes(to)) {
    throw badRequest(
      `A ${definition.label} that is "${from}" cannot become "${to}".`,
      [{
        field: type,
        message: allowed.length
          ? `Allowed next: ${allowed.join(', ')}.`
          : `A ${definition.label} of "${from}" is final.`,
      }]
    );
  }
}

/**
 * Cross-axis rules. Statuses are separate columns, but they are not independent
 * of each other, so these are checked whenever any of them changes.
 */
export function assertStatusCombination(next, current) {
  if (next.orderStatus === 'cancelled') return;

  if (next.completionStatus === 'completed') {
    if (current.paymentStatus !== 'paid' && next.paymentStatus !== 'paid') {
      throw badRequest(
        'A transaction can only be completed once payment is marked paid.',
        [{ field: 'completionStatus', message: 'Mark the payment as paid first.' }]
      );
    }
    if (
      next.deliveryStatus !== 'not_required' &&
      next.deliveryStatus !== 'delivered'
    ) {
      throw badRequest(
        'A transaction can only be completed once delivery is finished.',
        [{ field: 'completionStatus', message: 'Mark the delivery as delivered first.' }]
      );
    }
  }

  if (next.deliveryStatus !== 'not_required' && !next.deliveryRequired) {
    throw badRequest(
      'This transaction is not marked as needing delivery.',
      [{ field: 'deliveryStatus', message: 'Set "delivery required" to Yes first.' }]
    );
  }
}

/** The public shape of the four axes, plus the delivery flag. */
export function publicStatuses(row) {
  return {
    orderStatus: row.order_status,
    paymentStatus: row.payment_status,
    deliveryStatus: row.delivery_status,
    completionStatus: row.completion_status,
    deliveryRequired: Boolean(row.delivery_required),
  };
}
