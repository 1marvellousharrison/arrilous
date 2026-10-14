import { IntegrationService, reservedMethod } from './extension.js';

/**
 * Phase 14 — WhatsApp boundary.
 *
 * Future flow (product spec Phase 2): a customer message arrives on a webhook,
 * the service (optionally) produces an AI reply, and a confirmed order becomes a
 * transaction draft with `source = 'whatsapp'`. Automation must always be
 * switch-off-able and must be able to hand a conversation to a human.
 *
 * Reserved now; no WhatsApp API, webhook, or AI call is made.
 */
class WhatsAppService extends IntegrationService {
  constructor() {
    super(
      'whatsapp',
      'Inbound WhatsApp messages, AI replies, order drafts, and human takeover.',
      [
        'receiveInboundMessage',
        'sendMessage',
        'extractOrderDraft',
        'setAutomationEnabled',
        'handOffToHuman',
      ]
    );
  }

  /** Handle one inbound webhook message. Returns nothing until implemented. */
  async receiveInboundMessage() {
    throw reservedMethod(this.name, 'receiveInboundMessage');
  }

  /** Send a free-form or templated message back to a customer. */
  async sendMessage() {
    throw reservedMethod(this.name, 'sendMessage');
  }

  /** Turn a conversation into an order draft (`source: 'whatsapp'`). */
  async extractOrderDraft() {
    throw reservedMethod(this.name, 'extractOrderDraft');
  }

  /** Toggle automatic replies on/off for a business. */
  async setAutomationEnabled() {
    throw reservedMethod(this.name, 'setAutomationEnabled');
  }

  /** Stop automation for a thread and flag it for the owner (spec 19–20). */
  async handOffToHuman() {
    throw reservedMethod(this.name, 'handOffToHuman');
  }
}

export const whatsappService = new WhatsAppService();
