import { IntegrationService, reservedMethod } from './extension.js';

/**
 * Phase 14 — logistics boundary.
 *
 * Future flow (product spec Phase 3–4): a delivery-required transaction is
 * matched to partners by service area, availability, distance, price, capacity,
 * and status; a delivery request is created; rider updates move `delivery_status`
 * through `pending → accepted → picked_up → in_transit → delivered`. Failed
 * deliveries are recorded (never deleted) so the owner can retry or reschedule.
 *
 * Reserved now; no partner, rider, or location-matching API is called.
 */
class LogisticsService extends IntegrationService {
  constructor() {
    super(
      'logistics',
      'Partner matching, delivery requests, rider tracking, and delivery confirmation.',
      ['matchPartners', 'createDeliveryRequest', 'applyProviderUpdate', 'confirmDelivery']
    );
  }

  /** Rank candidate partners for a delivery, given its location and type. */
  async matchPartners() {
    throw reservedMethod(this.name, 'matchPartners');
  }

  /** Create a delivery request against the chosen partner. */
  async createDeliveryRequest() {
    throw reservedMethod(this.name, 'createDeliveryRequest');
  }

  /** Apply a rider/partner update to `delivery_status` through the status service. */
  async applyProviderUpdate() {
    throw reservedMethod(this.name, 'applyProviderUpdate');
  }

  /**
   * Confirm a delivery with a customer OTP and/or proof (photo, timestamp, GPS,
   * signature) and record who confirmed, when, and where.
   */
  async confirmDelivery() {
    throw reservedMethod(this.name, 'confirmDelivery');
  }
}

export const logisticsService = new LogisticsService();
