import { whatsappService } from './whatsapp.js';
import { paymentService } from './payments.js';
import { logisticsService } from './logistics.js';
import { notificationService } from './notifications.js';

/**
 * Phase 14 — the integration registry.
 *
 * These four are the only places allowed to hold an external provider detail.
 * They are imported but not called anywhere: the transaction core is complete
 * without them, and they exist so a later phase can implement a provider behind
 * an interface the rest of the app already knows.
 */
export const services = Object.freeze({
  whatsapp: whatsappService,
  payments: paymentService,
  logistics: logisticsService,
  notifications: notificationService,
});

/** A stable description of every boundary, for tests and future status output. */
export function integrationCapabilities() {
  return Object.values(services).map((service) => service.describe());
}

export {
  whatsappService,
  paymentService,
  logisticsService,
  notificationService,
};
