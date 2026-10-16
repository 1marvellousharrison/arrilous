import crypto from 'node:crypto';
import { queryAll, run } from '../db/index.js';

/**
 * Phase 8 — the append-only status timeline.
 *
 * The status columns answer "what is this sale now?". This answers "how did it
 * get here?", which is the question behind every dispute about a payment that
 * did not land or a delivery that disappeared.
 *
 * Two rules hold this table together:
 *
 *  1. Nothing here is ever updated or deleted. There is no updated_at column by
 *     design, and the only writer is recordStatusChange below. An audit trail
 *     that can be edited is not an audit trail.
 *  2. No entry is written for a no-op. Sending the value a transaction already
 *     has is not an event, and recording it would pad the timeline with noise
 *     that hides the changes that actually happened.
 */

export const STATUS_AXES = ['order', 'payment', 'delivery', 'completion'];

/** Maps a transactions row to the current value of each axis. */
export function currentAxes(row) {
  return {
    order: row.order_status,
    payment: row.payment_status,
    delivery: row.delivery_status,
    completion: row.completion_status,
  };
}

/**
 * Appends one timeline entry.
 *
 * Callers pass the previous and next value for a single axis; this function does
 * the deciding about whether that counts as a change, so every write site stays
 * consistent about it.
 */
export async function recordStatusChange({
  transactionId,
  businessId,
  userId,
  type,
  oldValue,
  newValue,
  note = null,
}) {
  if (oldValue === newValue) return false;

  await run(
    `INSERT INTO transaction_status_history
       (id, transaction_id, business_id, changed_by_user_id,
        status_type, old_value, new_value, note, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    crypto.randomUUID(),
    transactionId,
    businessId,
    userId ?? null,
    type,
    oldValue ?? null,
    newValue,
    note ?? null,
    new Date().toISOString()
  );
  return true;
}

/**
 * Writes the four entries that describe how a transaction was born.
 *
 * old_value is NULL on all of them, so the timeline opens with the state the
 * sale started in rather than an empty list that every reader has to special
 * case.
 */
export async function recordCreation({
  transactionId,
  businessId,
  userId,
  order,
  payment,
  delivery,
  completion,
}) {
  const started = { order, payment, delivery, completion };
  const written = [];
  for (const type of STATUS_AXES) {
    if (
      await recordStatusChange({
        transactionId,
        businessId,
        userId,
        type,
        oldValue: null,
        newValue: started[type],
        note: 'Transaction created',
      })
    ) {
      written.push(type);
    }
  }
  return written;
}

/**
 * Records every axis that moved between two states.
 *
 * `previous` and `next` are the four-axis objects the Phase 7 rules already
 * compute, so the timeline cannot disagree with the columns: the same pair of
 * objects that passed assertStatusCombination is what gets written.
 */
export async function recordStatusDiff({
  transactionId,
  businessId,
  userId,
  previous,
  next,
  note = null,
}) {
  const written = [];
  for (const type of STATUS_AXES) {
    if (
      await recordStatusChange({
        transactionId,
        businessId,
        userId,
        type,
        oldValue: previous[type],
        newValue: next[type],
        note,
      })
    ) {
      written.push({ type, from: previous[type], to: next[type] });
    }
  }
  return written;
}

/**
 * Appends a standalone note with no status axis attached.
 *
 * A staff may annotate a sale but not move its status, and every note belongs in
 * the same append-only trail as the status moves, so this writes a 'note' entry
 * whose old_value and new_value are both NULL. Nothing about the sale's columns
 * changes; only the timeline grows.
 */
export async function recordNote({ transactionId, businessId, userId, note }) {
  const text = typeof note === 'string' ? note.trim() : '';
  if (!text) return false;

  await run(
    `INSERT INTO transaction_status_history
       (id, transaction_id, business_id, changed_by_user_id, status_type,
        old_value, new_value, note, created_at)
     VALUES (?, ?, ?, ?, 'note', NULL, NULL, ?, ?)`,
    crypto.randomUUID(),
    transactionId,
    businessId,
    userId ?? null,
    text,
    new Date().toISOString()
  );
  return true;
}

export function publicHistoryEntry(row) {
  return {
    id: row.id,
    transactionId: row.transaction_id,
    statusType: row.status_type,
    oldValue: row.old_value,
    newValue: row.new_value,
    note: row.note,
    changedByUserId: row.changed_by_user_id,
    createdAt: row.created_at,
  };
}

/** A transaction's timeline, oldest first. */
export async function historyFor(transactionId) {
  return (await queryAll(
    `SELECT * FROM transaction_status_history
      WHERE transaction_id = ?
      ORDER BY created_at ASC, seq ASC`,
    transactionId
  )).map(publicHistoryEntry);
}

/** The most recent activity across every transaction in a business. */
export async function recentHistory(businessId, limit = 20) {
  return (await queryAll(
    `SELECT h.*, t.transaction_number AS transaction_number
       FROM transaction_status_history h
       JOIN transactions t ON t.id = h.transaction_id
      WHERE h.business_id = ?
      ORDER BY h.created_at DESC, h.seq DESC
      LIMIT ?`,
    businessId,
    limit
  )).map((row) => ({
    ...publicHistoryEntry(row),
    transactionNumber: row.transaction_number,
  }));
}