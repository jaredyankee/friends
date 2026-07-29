import { SCHEDULE_CORE_VERSION } from '@friends/schedule-core';

import { PlaceholderScreen } from '../../../components/PlaceholderScreen';

/**
 * The import above is load-bearing beyond what it displays: it is the only
 * thing that makes Metro actually resolve a workspace package while bundling.
 * Without it, `expo export` proves the app builds but says nothing about
 * whether metro.config.js works. Keep an @friends/* import reachable from a
 * screen until real usage lands in A2.3.
 */
export default function CalendarScreen() {
  return (
    <PlaceholderScreen
      title="Calendar"
      description="Personal month, week, and agenda views, plus group composite calendars."
      landsIn={`Week view lands in A2.3 · schedule-core ${SCHEDULE_CORE_VERSION}`}
    />
  );
}
