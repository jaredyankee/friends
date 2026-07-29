/**
 * schedule-ui — React Native calendar component kit.
 *
 * Deliberately empty. Implementation lands in T2/T4 (see docs/roadmap.md); the
 * component and hook design is in docs/schedule-ui.md. This package exists now
 * so workspace resolution and CI have something real to resolve, and to prove
 * schedule-ui can import schedule-core across the workspace boundary.
 *
 * Rules that hold here permanently:
 *   - No I/O. Components take props; the app fetches.
 *   - No hard-coded color. Everything resolves from a CalendarTheme.
 *   - No Supabase, no app-domain concepts.
 */

import { SCHEDULE_CORE_VERSION } from '@friends/schedule-core';

export const SCHEDULE_UI_VERSION = '0.0.0';

/** Proves the cross-package import resolves under Metro, tsc, and Jest alike. */
export const linkedCoreVersion = (): string => SCHEDULE_CORE_VERSION;
