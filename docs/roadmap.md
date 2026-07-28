# Roadmap

The work tree. Three levels:

```
TASK          a phase of the project. Weeks. Done when all its actions are done.
  ACTION      one pull request. Done when its requirements are met and it's merged.
    REQUIREMENT   a checkable condition. Done or not done.
```

**Traversal.** Complete an action's requirements → open the PR → on merge, mark the action done and
move to the *next action in the same task*. Only when a task's actions are all done do we move to the
next task. Never jump branches mid-action without saying so.

**Detail decays with distance.** Tasks 1–3 have real requirements because we know enough to write
them. Tasks 4–6 are deliberately coarse; their requirements get written when the preceding task
lands. Treat far branches as shape, not commitment.

**Status key:** `[ ]` not started · `[~]` in progress · `[x]` done

---

## T1 — Foundation `[ ]`

Get a running app, a running database, and a place for the packages to live. Nothing here is
Friends-specific; it's the platform everything else sits on.

### A1.1 — Monorepo and Expo scaffold `[ ]`

- [ ] npm workspaces configured with `packages/*` and the app at root
- [ ] Expo (managed) + TypeScript strict, `npx tsc --noEmit` clean
- [ ] expo-router with the four tab routes stubbed: calendar, form, chat, account
- [ ] `metro.config.js` resolves workspace packages (`watchFolders`, `nodeModulesPaths`)
- [ ] ESLint + Prettier + Jest wired; `npm test` and `npm run lint` pass on an empty suite
- [ ] App boots in the iOS simulator and tab navigation works

### A1.2 — Supabase project and identity schema `[ ]`

- [ ] `supabase start` runs locally
- [ ] Migration creates `profiles`, `friendships`, `groups`, `group_members` per `docs/schema.md`
- [ ] RLS enabled with policies on all four, including the `is_group_member` security-definer helper
- [ ] Trigger creates a `profiles` row on `auth.users` insert
- [ ] `lib/database.types.ts` generated and committed
- [ ] Policy tests: a non-friend cannot read another profile's private fields

### A1.3 — Auth and session `[ ]`

- [ ] Sign up, sign in, sign out against Supabase Auth
- [ ] `(auth)` route group; unauthenticated users can't reach `(tabs)`
- [ ] Session context provider; TanStack Query client configured with the authed Supabase client
- [ ] Profile creation completes onboarding (handle, display name, time zone)
- [ ] Session persists across app restart

---

## T2 — schedule-core `[ ]`

The headless engine. Built and tested standalone, before anything renders it. Design lives in
`docs/schedule-core.md`.

### A2.1 — Types and interval algebra `[ ]`

- [ ] All types from the design doc, exported and documented
- [ ] `normalize`, `union`, `intersect`, `subtract`, `clip` implemented
- [ ] Unit tests including abutting, nested, and zero-length intervals
- [ ] Package builds standalone; dependency list is exactly `luxon` (no React, no Supabase)

### A2.2 — Zone-correct recurrence expansion `[ ]`

- [ ] `expandEvent` / `expandEvents` wrapping `rrule`, expanding in local wall-clock then converting
- [ ] Exceptions applied by `occurrenceStart`: cancellations and field overrides
- [ ] DST policy implemented and documented — spring-forward gaps shift forward, fall-back repeats
      take the first
- [ ] All-day events handled as local-midnight to local-midnight
- [ ] `maxOccurrences` guard throws rather than hanging on unbounded rules
- [ ] Golden fixtures as plain JSON covering: both DST transitions, cross-zone viewing, non-hour
      offsets, anchor predating range, exception-heavy items

### A2.3 — Free/busy, availability, and sources `[ ]`

- [ ] `toFreeBusy` and `computeAvailability` with `minDurationMinutes`, `granularityMinutes`,
      `quorum`, `within`
- [ ] `ScheduleSource` interface and `createResolver` with per-source failure reporting
- [ ] Tests: single participant, all-free, none-free, partial quorum, empty range
- [ ] Public API reviewed for vendor-type leakage before anything depends on it

---

## T3 — Schedule data layer `[ ]`

Wire the engine to real data. Where the visibility model gets proven rather than described.

### A3.1 — Schedule item schema `[ ]`

- [ ] Migration: `schedule_items`, `schedule_item_exceptions`, `schedule_item_shares`
- [ ] `effective_visibility` function and RLS policies per `docs/schema.md`
- [ ] `visible_schedule_items` view with `security_invoker = true` and column redaction
- [ ] Regenerated `database.types.ts` in the same PR
- [ ] Policy tests, the important ones: `busy` viewer receives null title; `hidden` item returns no
      row; share grant to a group raises level for members only; owner sees everything

### A3.2 — Supabase source and query layer `[ ]`

- [ ] `lib/schedule-source.ts` implements `ScheduleSource` over `visible_schedule_items`
- [ ] snake_case → camelCase conversion at this boundary only
- [ ] TanStack Query hooks for range fetches, with cache keys including the viewer
- [ ] Round-trip test: rows in Postgres → `CalendarEvent` → occurrences → expected result

### A3.3 — Server-side availability `[ ]`

- [ ] `group_availability` RPC returning the `AvailabilityWindow` shape verbatim
- [ ] Parity harness runs core's golden fixtures against the SQL implementation
- [ ] Documented decision on which path the app uses when, and why

---

## T4 — schedule-ui `[ ]`

The component kit. Design in `docs/schedule-ui.md`. Requirements firm up after T2 lands.

### A4.1 — Theme contract and provider `[ ]`

Shape: `CalendarTheme` type, `CalendarProvider`, default theme, a lint rule or test that fails on a
color literal inside the package.

### A4.2 — Time grid spike, then WeekView and DayView `[ ]`

Shape: build one week view twice — wrapping `@howljs/calendar-kit` and hand-rolled on Reanimated —
compare on theming control, gesture fidelity, and bundle cost. Decide, then build the real thing
behind our own API. **This is the spike that unblocks the rest of T4.**

### A4.3 — MonthView and AgendaList `[ ]`

Shape: month grid with `renderDayIndicator`; agenda on FlashList with section headers and empty states.

### A4.4 — Availability views `[ ]`

Shape: `AvailabilityStrip`, `GroupAvailabilityView`, the who's-free interaction. The differentiated
surface — no prior art to lean on.

---

## T5 — App modes `[ ]`

Assembling the kit and the data layer into the four tabs. Coarse by design; refine when T4 lands.

### A5.1 — Calendar mode `[ ]`
Personal month/week/agenda, view switching, cursor navigation, zone labelling.

### A5.2 — Form mode `[ ]`
Create and edit schedule items, recurrence editor, visibility picker. Must make the "hidden means you
appear free" consequence visible at the point of choosing it.

### A5.3 — Photo import `[ ]`
Storage upload → `parse-schedule-image` Edge Function → review-and-confirm UI. Never writes directly
to the calendar; see CLAUDE.md.

### A5.4 — Friends and groups `[ ]`
Friend requests and acceptance, group creation and membership, group composite calendar.

---

## T6 — Social and polish `[ ]`

### A6.1 — Chat `[ ]`
Per-group threads over Supabase Realtime.

### A6.2 — Theming and palettes `[ ]`
User-selectable palettes, light/dark, contrast verification across every shipped palette.

### A6.3 — Accessibility pass `[ ]`
Screen reader labels, Dynamic Type, hit targets, non-gesture fallbacks for drag interactions.

---

## Deferred

Named so they don't get silently forgotten, not scheduled:

- Push notifications (Expo push vs. APNs) — decision open in CLAUDE.md
- iOS system calendar sync via EventKit
- Explicit "event" object for confirmed plans vs. plain schedule items
- Free-tier limits: group count, message retention
- Web support for `schedule-ui` via react-native-web
- Recurring-event editing UI ("this / this and following / all")
