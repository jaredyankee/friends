/**
 * schedule-core — headless scheduling engine.
 *
 * Deliberately empty. Implementation lands in T2 (see docs/roadmap.md); the API
 * design is in docs/schedule-core.md. This package exists now so the workspace
 * wiring, Metro resolution, and CI have something real to resolve.
 *
 * Two rules hold here permanently:
 *   - No I/O. Pure functions over plain serializable data.
 *   - No React, no Expo, no Supabase, no app-domain concepts. This has to stay
 *     importable from Edge Functions and the SQL availability path.
 */

/** ISO 8601 instant, always UTC at rest. "2026-03-08T14:00:00.000Z" */
export type Instant = string;

/** IANA zone identifier. "America/New_York" */
export type TimeZone = string;

export interface Interval {
  start: Instant;
  end: Instant;
}

/** Placeholder so the module has a runtime export and bundlers resolve it. */
export const SCHEDULE_CORE_VERSION = '0.0.0';
