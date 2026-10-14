import { IntegrationService, reservedMethod } from './extension.js';

/**
 * Phase 14 — notification boundary.
 *
 * Future flow: fan out push/email/WhatsApp events — order detected, paid,
 * picked up, delivered, failed, human attention needed. Notifications are a
 * side effect of a status change, never a cause of one, so they must not be
 * able to fail a transaction write.
 *
 * Reserved now; nothing is sent anywhere.
 */
class NotificationService extends IntegrationService {
  constructor() {
    super(
      'notifications',
      'Fan-out of push/email/WhatsApp events to owners and customers.',
      ['send', 'notifyOwner', 'notifyCustomer']
    );
  }

  /** Send one event to one recipient over the configured channels. */
  async send() {
    throw reservedMethod(this.name, 'send');
  }

  /** Notify the owning business (new order, payment received, attention needed). */
  async notifyOwner() {
    throw reservedMethod(this.name, 'notifyOwner');
  }

  /** Notify a customer (order confirmed, out for delivery, delivered). */
  async notifyCustomer() {
    throw reservedMethod(this.name, 'notifyCustomer');
  }
}

export const notificationService = new NotificationService();
