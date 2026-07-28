# Roadmap — v1

The work tree. Three levels:

```
TASK          a phase of the project. Done when all its actions are done.
  ACTION      one pull request. Done when its requirements are met and it's merged.
    REQUIREMENT   a checkable condition. Done or not done.
```

**Traversal.** Complete an action's requirements → open the PR → on merge, mark the action done and
move to the *next action in the same task*. Only when a task's actions are all done do we move to the
next task. Never jump branches mid-action without saying so.

**Detail decays with distance.** T1–T3 have real requirements because we know enough to write them.
T4–T8 are deliberately coarse and marked provisional; their requirements get written when the
preceding task lands. Treat far branches as shape, not commitment.

**Status key:** `[ ]` not started · `[~]` in progress · `[x]` done

---

## v1 definition of done

A public App Store release containing: personal schedules with recurring items, per-item visibility
with group and individual grants, friends and groups with invite links, group composite calendars with
availability highlighting and who's-free detail, per-group chat, and user-selectable light/dark themes.

**Deferred to post-v1:** schedule photo import. This is the README's headline feature and v1 ships
without it — a deliberate scope call, recorded here so it isn't mistaken for an oversight.

---

## T1 — Foundation `[ ]`

A running app, a running database, and the CI to keep them honest. Nothing Friends-specific.

### A1.1 — Monorepo, Expo scaffold, CI `[ ]`

- [ ] npm workspaces with `packages/*`, app at root
- [ ] Expo (managed) + TypeScript strict; `npx tsc --noEmit` clean
- [ ] expo-router with four tab routes stubbed: calendar, form, chat, account
- [ ] `metro.config.js` resolves workspace packages (`watchFolders`, `nodeModulesPaths`)
- [ ] ESLint + Prettier + Jest; `npm test` and `npm run lint` pass
- [ ] GitHub Actions runs typecheck, lint, and tests on every PR
- [ ] `.env` handling for local vs. production Supabase, with no secrets committed
- [ ] App boots in the iOS simulator and tabs navigate

### A1.2 — Identity schema `[ ]`

- [ ] `supabase start` runs locally
- [ ] Migration creates `profiles`, `friendships`, `groups`, `group_members` per `docs/schema.md`
- [ ] RLS enabled with policies on all four, including the `is_group_member` security-definer helper
- [ ] Trigger creates a `profiles` row on `auth.users` insert
- [ ] Seed script produces a usable dev dataset: several profiles, a friendship, a group
- [ ] `lib/database.types.ts` generated and committed
- [ ] Policy test: a non-friend cannot read another profile's private fields

### A1.3 — Auth, session, onboarding `[ ]`

- [ ] Sign up, sign in, sign out against Supabase Auth
- [ ] `(auth)` route group; unauthenticated users cannot reach `(tabs)`
- [ ] Session context provider; TanStack Query configured with the authed client
- [ ] Onboarding captures handle, display name, and time zone
- [ ] Session persists across app restart

---

## T2 — Vertical slice `[ ]`

The thinnest end-to-end path, built to validate both package APIs against real usage while they are
still cheap to change. **This task ends with a working app**, not a tested library.

### A2.1 — schedule-core v0 `[ ]`

- [ ] Types from `docs/schedule-core.md`, exported and documented
- [ ] `normalize`, `union`, `intersect`, `subtract`, `clip` implemented
- [ ] Single-occurrence expansion only — no RRULE yet
- [ ] Unit tests covering abutting, nested, and zero-length intervals
- [ ] Builds standalone; dependencies are exactly `luxon` (no React, no Supabase)

### A2.2 — Schedule item schema and source `[ ]`

- [ ] Migration: `schedule_items`, `schedule_item_exceptions`, `schedule_item_shares`
- [ ] `effective_visibility` function, RLS policies, and the `visible_schedule_items` view with
      `security_invoker = true`
- [ ] Regenerated `database.types.ts` in the same PR
- [ ] `lib/schedule-source.ts` implements `ScheduleSource`; snake_case → camelCase converts here only
- [ ] Round-trip test: rows → `CalendarEvent` → occurrences → expected output

### A2.3 — schedule-ui v0 `[ ]`

- [ ] Time-grid spike: build one week view wrapping `@howljs/calendar-kit` and one hand-rolled on
      Reanimated; compare theming control, gesture fidelity, bundle cost; **record the decision**
- [ ] `CalendarTheme` contract, `CalendarProvider`, default theme
- [ ] `useTimeGridLayout` with overlap packing, unit-tested as a pure function
- [ ] `WeekView` renders occurrences behind our own API, no vendor types in the public surface
- [ ] A test or lint rule fails on a color literal inside the package

### A2.4 — End-to-end proof `[ ]`

- [ ] Form tab creates and edits a non-recurring schedule item
- [ ] Calendar tab renders it in the week view, in the viewer's zone
- [ ] TanStack Query cache keys include the viewer; edits reflect without a manual refresh
- [ ] Walk the slice on a device and write down what the package APIs got wrong — that list feeds T3

---

## T3 — Recurrence `[ ]`

### A3.1 — Zone-correct expansion `[ ]`

- [ ] `expandEvent` / `expandEvents` wrapping `rrule`, expanding in local wall-clock then converting
- [ ] DST policy implemented and documented — spring-forward gaps shift forward, fall-back repeats
      take the first
- [ ] All-day events as local-midnight to local-midnight
- [ ] `maxOccurrences` guard throws rather than hanging on unbounded rules
- [ ] Golden fixtures as plain JSON: both DST transitions, cross-zone viewing, non-hour offsets,
      anchor predating range

### A3.2 — Exceptions `[ ]`

- [ ] Exceptions applied by `occurrenceStart`: cancellations and field overrides
- [ ] Exception-heavy fixtures pass
- [ ] Recurring items render correctly in the week view across a DST boundary

### A3.3 — Recurrence in the Form tab `[ ]`

- [ ] Recurrence editor producing valid RFC 5545 RRULE strings
- [ ] Editing one instance of a series writes an exception, never mutates the parent rule
- [ ] "This event / this and following / all events" interaction

---

## T4 — Visibility and social graph `[ ]`

*Provisional — requirements firm up when T3 lands.*

### A4.1 — Visibility end-to-end `[ ]`
Visibility picker in the Form tab; RLS policy tests as the merge gate (a `busy` viewer receives null
title; a `hidden` item returns no row; a group grant raises the level for members only). The UI must
make the "hidden means you appear free" consequence visible at the point of choosing it.

### A4.2 — Friends `[ ]`
Discovery by handle, requests, acceptance, removal. Empty states for an account with no friends.

### A4.3 — Groups and invite links `[ ]`
Group creation, membership, roles. New `group_invites` table — token, group, creator, expiry, max
uses, revocation — plus the deep-link route that redeems one.

---

## T5 — Availability `[ ]`

*Provisional.* The product thesis — the reason the app exists.

### A5.1 — Availability in core `[ ]`
`toFreeBusy` and `computeAvailability` with `minDurationMinutes`, `granularityMinutes`, `quorum`,
`within`. `ScheduleSource` resolver with per-source failure reporting.

### A5.2 — Server-side availability `[ ]`
`group_availability` RPC returning the `AvailabilityWindow` shape verbatim, plus a parity harness
running core's golden fixtures against the SQL implementation.

### A5.3 — Group composite calendar `[ ]`
A group's combined calendar, respecting each viewer's effective visibility.

### A5.4 — Availability surfaces `[ ]`
Heatmap, all-free highlighting, tap-a-block-to-see-who's-free, filter by person.

---

## T6 — Chat `[ ]`

*Provisional.* Minimal by design: text only, no push, no media.

### A6.1 — Messages schema `[ ]`
`messages` table with RLS restricting reads and writes to group members.

### A6.2 — Thread UI `[ ]`
Per-group threads over Supabase Realtime, on FlashList, with optimistic send.

---

## T7 — Kit completion and polish `[ ]`

*Provisional.*

### A7.1 — MonthView and AgendaList `[ ]`
### A7.2 — Drag to create, move, resize `[ ]`
### A7.3 — Themes, palettes, and item colors `[ ]`
User-selectable palettes, light/dark, contrast verified on every shipped palette. Includes the
README's per-item color coding: a color picker in the Form tab writing `schedule_items.color_key`,
resolved through the theme's `occurrence` map so item colors follow the chosen palette rather than
being stored as hex.
### A7.4 — Accessibility pass `[ ]`
Screen reader labels, Dynamic Type, hit targets, non-gesture fallbacks for every drag interaction.
### A7.5 — Timezone changes `[ ]`
Detect when a user's device zone differs from their profile zone; decide and implement the behavior.

---

## T8 — Release `[ ]`

*Provisional.* Not optional, and not discovered during review.

### A8.1 — Account deletion and data export `[ ]`
In-app account deletion is **required by App Store guidelines** for any app with signup. Cascade
behavior across items, shares, groups, and messages needs deciding, not defaulting.

### A8.2 — Error, empty, and offline states `[ ]`
Systematic pass across all four tabs, plus crash reporting.

### A8.3 — EAS Build and TestFlight `[ ]`
Build profiles, signing, internal distribution, and a real install on a real device.

### A8.4 — App Store submission `[ ]`
Screenshots, app icon, privacy policy URL, App Privacy disclosures, support URL, review iterations.

---

## Post-v1

Named so they aren't silently forgotten:

- **Schedule photo import** — Storage → `parse-schedule-image` Edge Function → review-and-confirm UI.
  Design retained in `CLAUDE.md` and `docs/schema.md`. Needs cost controls and an image deletion
  lifecycle before it ships.
- Push notifications (Expo push vs. APNs) — decision still open
- iOS system calendar sync via EventKit
- Explicit plan/event object for confirmed plans
- Public availability links (Calendly-shaped) — needs a safe unauthenticated read path
- Web support for `schedule-ui` via react-native-web
- Recurring-event editing beyond the basics
- Free-tier limits: group count, message retention
