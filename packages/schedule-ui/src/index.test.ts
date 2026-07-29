import { SCHEDULE_CORE_VERSION } from '@friends/schedule-core';

import { linkedCoreVersion, SCHEDULE_UI_VERSION } from './index';

/**
 * This suite exists to prove the workspace wiring, not the logic — there is no
 * logic yet. If schedule-ui can import schedule-core here, then the npm
 * workspace links, the tsconfig paths, and the Jest moduleNameMapper all agree.
 * When that breaks, it breaks confusingly, so it's worth a test from day one.
 */
describe('workspace linking', () => {
  it('resolves schedule-core from schedule-ui', () => {
    expect(linkedCoreVersion()).toBe(SCHEDULE_CORE_VERSION);
  });

  it('exposes its own version', () => {
    expect(SCHEDULE_UI_VERSION).toBe('0.0.0');
  });
});
