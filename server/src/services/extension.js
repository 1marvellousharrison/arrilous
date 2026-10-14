import { ApiError } from '../lib/errors.js';
import { config } from '../config.js';

/**
 * Phase 14 — the shared shape behind every integration boundary.
 *
 * A service owns exactly one external concern and nothing else. Routes and the
 * transaction core call a service; they never talk to a provider directly. That
 * is the seam that lets a provider be swapped, or added, without touching the
 * manual-sale path.
 *
 * Nothing here makes a network call. Each method is a reserved slot that throws
 * until a later phase fills it in, so the interfaces can be reviewed and wired
 * into tests now without any integration actually being live.
 */
export function reservedMethod(service, method) {
  // 501, not 500: "not built yet" must be distinguishable from "the provider
  // failed", or a caller would treat a missing integration as an outage.
  return new ApiError(
    501,
    'not_implemented',
    `${service}.${method}() is a reserved integration point and is not implemented yet.`,
    [{ field: 'service', message: 'This integration arrives in a later phase.' }]
  );
}

export class IntegrationService {
  constructor(name, summary, methods) {
    this.name = name;
    this.summary = summary;
    this.methods = Object.freeze([...methods]);
    for (const method of methods) {
      if (typeof this[method] !== 'function') {
        throw new Error(`${name} declares method "${method}" but does not define it.`);
      }
    }
  }

  /**
   * A provider name in the environment is the only thing that turns a service
   * "on". The credential itself is read where it is used, never stored here.
   */
  get configured() {
    return Boolean(config.integrations[this.name]?.provider);
  }

  get provider() {
    return config.integrations[this.name]?.provider ?? null;
  }

  /** Machine-readable description, used by the tests and future status pages. */
  describe() {
    return {
      name: this.name,
      summary: this.summary,
      configured: this.configured,
      methods: [...this.methods],
    };
  }
}
