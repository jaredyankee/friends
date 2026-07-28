# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

**Friends** is an iOS-first mobile app for coordinating plans between people. Each user keeps a
schedule; schedules can be shared with individuals or groups; a group's calendar is the composite of
its members' schedules, and the app surfaces the windows when everyone is free.

The product spec lives in `README.md`. This file covers how we build it.

- `docs/schema.md` — the data model. Read before touching anything that reads or writes schedule data.
- `docs/schedule-core.md` — the headless scheduling engine. Read before touching recurrence,
  free/busy, or availability logic.
- `docs/schedule-ui.md` — the React Native calendar component kit. Read before touching calendar
  views, gestures, or layout.

## Current state

Greenfield. The repo contains `README.md`, `LICENSE`, `package.json`, and these docs. No application
code exists yet. Commands listed below describe the intended setup and will not run until the app is
scaffolded — say so plainly rather than pretending a step succeeded.

## Communicating with the repo owner

Work arrives as PRs the owner reviews, and the owner is not watching it happen. Write for someone
catching up, not for a log file.

**End every message with a "Next up" block.** A short numbered list of the concrete options
available now — each one sentence covering what it does and what it costs or unlocks. Anything that
needs the owner's input goes in that block.

Rules that make the block worth reading:

- **Never scatter asks through the body.** If the owner needs to do something, decide something, or
  answer something, it belongs in "Next up" and nowhere else. A request buried in paragraph three is
  a request that gets missed.
- **Lead with the outcome.** First sentence answers "what happened" or "what did you find". Detail
  and reasoning come after, for whoever wants them.
- **Mark the one-way doors.** Call out explicitly when a choice is expensive to reverse later
  (a stack commitment, a published package API, a shipped migration) versus cheap to change. Those
  deserve the owner's attention; the rest usually doesn't.
- **Don't ask permission for reversible things.** Make the routine call, state which way you went,
  and move on. Save the questions for choices where the answer changes the work.
- **Say what you didn't do.** If part of the task was skipped, blocked, or deliberately deferred,
  name it plainly rather than letting a clean summary imply it's done.
- Keep options to a handful. A list of nine choices is the same as no recommendation — if one option
  is clearly right, put it first and say so.

**Propose amendments to this file when you find a gap.** Standing permission, no need to ask first.
If a conversation reveals that a decision recorded here was based on a misread of the owner's intent,
or that something load-bearing was never written down, amend the file in the same change and say what
you changed and why. Two rules: name the gap plainly rather than quietly editing around it — "I scoped
X as Y, you meant Z" — and don't reverse a decision the owner made explicitly. Surfacing that a
decision now looks wrong is useful; overwriting it is not.

## Stack (decisions of record)

| Layer | Choice | Why |
| --- | --- | --- |
| App | React Native via **Expo** (managed), **TypeScript** strict | iOS-first, Android nearly free later. Shares TS types with the DB. |
| Routing | **expo-router** | File-based routes, typed links, matches the four-mode structure below. |
| Backend | **Supabase** — Postgres, Auth, Realtime, Storage, Edge Functions | Row-level security maps directly onto the visibility rules; Realtime covers chat and live calendar updates. |
| Calendar UI | Custom surfaces built on **react-native-reanimated** + **react-native-gesture-handler**, lists via **@shopify/flash-list** | The week grid, drag-to-create, and the group availability heatmap are custom-drawn. No off-the-shelf calendar component will carry them. |
| Dates | **Luxon** for zone-aware math, **rrule** for RFC 5545 recurrence | See "Time rules" — this is the part most likely to be got wrong. |
| State | **TanStack Query** for server state, React context for session/theme | Don't add Redux/Zustand without a concrete reason. |

Do not swap any of these out as a side effect of another change. If one of them is genuinely the
wrong tool for a task, say so and let the owner decide.

## The four modes

Navigation is a tab bar with exactly four destinations. Resist adding a fifth.

1. **Calendar** — personal month/week/agenda views, plus group composite calendars.
2. **Form** — create and edit schedule items; also where a work-schedule photo is uploaded.
3. **Chat** — per-group messaging.
4. **Account** — profile, friends, groups, theme, visibility defaults.

## Architecture: the calendar kit

The calendar — logic *and* UI — is a reusable kit, not app code. It is built to be consumed by other
projects that draw calendar data from entirely different sources. Friends is its first consumer, not
its owner.

Two packages, published together and versioned in lockstep:

| Package | Holds | Depends on |
| --- | --- | --- |
| `schedule-core` | Recurrence expansion, interval algebra, free/busy, availability | `rrule`, `luxon`. Nothing else. |
| `schedule-ui` | React Native views, gestures, layout hooks, theming | `schedule-core`; peers: react, react-native, reanimated, gesture-handler |

Designs: `docs/schedule-core.md` and `docs/schedule-ui.md`.

**Why the split.** `schedule-core` has to be importable where React cannot go — Supabase Edge
Functions, the SQL availability path, any server-side consumer. Bundling components into it would drag
React Native into a database function. Apps install both packages; the split costs an extra dependency
line and buys a core that runs anywhere.

Rules that hold across both:

- **Neither package imports Supabase, Expo, or app-domain concepts.** No visibility levels, no
  `profiles` table, no group concept. Friends' visibility system resolves in Postgres and hands the kit
  *already-filtered* data — see the mapping table in `docs/schedule-core.md`.
- **Nothing calendar-shaped goes in the app.** Interval arithmetic, DST handling, overlap packing, and
  time-grid layout belong in the packages. If you're writing any of that under `app/` or `features/`,
  it's in the wrong place.
- **Neither package does I/O.** Core takes data, UI takes props. Fetching, caching, and auth are the
  app's job.
- **Public APIs are contracts.** Once a second project depends on them, a signature change costs a
  coordinated release. Additions are cheap; changes are expensive; vendor types must never leak through
  a public API, or swapping an internal renderer becomes a breaking change.
- **ISO 8601 strings at every boundary, not `Date` objects.** Data crosses HTTP, RPC, and process
  boundaries unchanged, and test fixtures stay plain JSON.
- **Theme in, no colors out.** `schedule-ui` hard-codes no color. It takes a theme object, which is
  what lets Friends' user-selectable palettes and another app's design language both work.

## Planned layout

```
packages/
  schedule-core/            # headless engine — zero app dependencies
    src/
    test/fixtures/          # golden cases: DST, cross-zone, exceptions
  schedule-ui/              # React Native calendar kit
    src/
      components/           # MonthView, WeekView, DayView, AgendaList, availability views
      hooks/                # layout, cursor, drag, now-indicator
      theme/                # CalendarTheme contract + default theme
app/                        # expo-router routes
  (tabs)/
    calendar/               # personal + group calendar views
    form/                   # schedule item create/edit, photo import
    chat/                   # group message threads
    account/                # profile, friends, groups, settings
  (auth)/                   # sign-in / sign-up
components/                 # shared presentational components
features/                   # feature-scoped logic (schedule/, groups/, chat/, availability/)
lib/
  supabase.ts               # typed client
  database.types.ts         # generated — never hand-edit
  schedule-source.ts        # Supabase implementation of the core's ScheduleSource
theme/                      # tokens, light/dark, user-selectable palettes
supabase/
  migrations/               # timestamped SQL, forward-only
  functions/
    parse-schedule-image/   # Edge Function: photo -> structured shifts
docs/schema.md              # the data model
```

Feature logic goes in `features/`, not in route files. Route files wire things together and stay thin.

## Commands

```bash
npx expo start                      # dev server
npx expo run:ios                    # build + run on simulator
npx tsc --noEmit                    # typecheck
npm run lint                        # eslint
npm test                            # jest (app)

npm test      -w schedule-core      # engine tests — run before any core change lands
npm test      -w schedule-ui        # layout math + component render tests
npm run build -w schedule-core -w schedule-ui

supabase start                      # local Postgres + Auth + Storage
supabase migration new <name>       # create a migration
supabase db reset                   # replay all migrations locally
supabase gen types typescript --local > lib/database.types.ts
```

Regenerate `lib/database.types.ts` after every migration and commit it in the same change.

## Domain model

Use this vocabulary consistently — in code, in schemas, in commit messages, in UI copy.

- **Friend** — a user account. Friendship is mutual and requires acceptance.
- **Group** — a named set of friends with a composite calendar and a message thread.
- **Schedule item** — one block of time on a friend's calendar. Items mark the owner *unavailable*
  by default; availability is the absence of items, not a stored value.
- **Occurrence** — a single materialized instance of a schedule item. A non-recurring item has one
  occurrence; a recurring item has many, generated from its rule at query time.
- **Availability window** — a computed span in which a given set of people have no overlapping
  occurrences. Never stored; always derived.

### Visibility

Two orthogonal axes. Keep them separate — conflating them is the most likely source of privacy bugs.

**Audience** — *who* can see the item at all: the owner only, all friends, specific groups, or
specific individuals.

**Detail level** — *what* they see. Three levels, ordered:

| Level | The viewer sees |
| --- | --- |
| `hidden` | Nothing. The owner appears free during this block. |
| `busy` | An opaque block. Time is taken; no title, no location, no notes. This is the README's "ambiguous" mode and the default. |
| `details` | Title, location, and notes. The README's "transparent" mode — "I am at work 9am–5pm". |

An item carries a `default_visibility` that applies to all of the owner's friends, plus zero or more
*share* grants that raise the level for a specific group or individual. Grants only ever raise;
they never lower. A viewer's effective level is the highest level granted to them by any path.

**Rules that must hold everywhere:**

- Effective visibility is enforced in Postgres via RLS, not in the client. The client must never be
  the only thing standing between a viewer and a title they shouldn't see.
- A `hidden` item does not contribute to availability calculations for that viewer. This is
  deliberate: hiding an item means appearing free, and the UI should make that consequence clear
  when a user picks it.
- Never send a field the viewer isn't entitled to and rely on the UI to omit it. Views and RLS
  policies strip `title`, `location`, and `notes` at the `busy` level.

### Availability

Group availability is computed, never stored:

1. Expand every member's items into occurrences over the requested range.
2. Drop occurrences the viewer cannot see (`hidden` for them).
3. Subtract the union of remaining occurrences from the range.
4. What's left is the availability window set. Windows where *every* member is free get the
   all-clear highlight.

Availability is always relative to a viewer. Two members of the same group can legitimately see
different availability for the same third person. Never cache a computed availability set across
viewers.

## Time rules

Read these before writing any date code. They are the invariants most likely to be violated.

- Store instants as `timestamptz` (UTC). Store the item's originating IANA zone alongside it in
  `time_zone`.
- **Expand recurrence in the item's local wall-clock time, then convert to UTC.** A "every weekday
  at 9am" shift stays at 9am local across a DST boundary; expanding in UTC silently shifts it by an
  hour for half the year.
- Recurrence rules are RFC 5545 `RRULE` strings. Do not invent a custom recurrence format.
- Exceptions to a recurring item (a cancelled or moved instance) are rows in
  `schedule_item_exceptions`, keyed by the original occurrence start. Never mutate the parent rule to
  express a one-off change.
- All-day items are stored as local-midnight-to-local-midnight in the item's zone, not as a
  separate date type.
- Render in the *viewer's* current zone, and label the zone whenever it differs from the item's.

## Schedule photo import

The README's headline feature: photograph a work schedule, get shifts on the calendar.

Flow: image → Supabase Storage → Edge Function `parse-schedule-image` → structured shifts → user
confirms in the Form tab → rows inserted.

Implementation notes for that Edge Function:

- Call Claude through the official SDK (`@anthropic-ai/sdk`), model `claude-opus-5`.
- Use structured outputs (`client.messages.parse()` with `output_config.format`) so the returned
  shifts validate against a schema — do not parse free-form text.
- Adaptive thinking is on by default on this model; `max_tokens` caps thinking *plus* output, so
  leave headroom (~16000 for a non-streaming call).
- Never write parsed shifts straight to the calendar. The extraction is a *proposal*; the user
  confirms or edits it in the Form tab first. Photographed schedules are smudged, cropped, and
  ambiguous, and silently inserting a wrong shift is worse than asking.
- The API key lives in Edge Function secrets. It never ships in the app bundle.

## Theming

Per the README: one primary color, a few shades of it, white text on the primary (inverted in dark
mode), light and dark, user-selectable palettes.

- All color goes through theme tokens. No hard-coded hex values in components — a literal color in a
  component is a bug, because it won't follow the user's chosen palette or their light/dark setting.
- Both modes must be legible for every shipped palette. Check contrast on text over the primary.
- Availability states (free / partially free / busy) are among the tokens, and must stay
  distinguishable without relying on hue alone.
- The app's palette maps onto `schedule-ui`'s `CalendarTheme` contract (`docs/schedule-ui.md`). The kit
  ships a default theme; Friends overrides it. Adding a palette should never require touching the kit.

## Conventions

- TypeScript strict. No `any` in committed code; if a type is genuinely unknown, use `unknown` and
  narrow it.
- Database identifiers are `snake_case`; TypeScript is `camelCase`. Convert at the data-access
  boundary, not scattered through components.
- Migrations are forward-only and never edited after they're pushed. Fix a mistake with a new
  migration.
- Every table with user data gets RLS enabled and explicit policies in the same migration that
  creates it. A table without policies is a leak.
- Tests: full unit coverage of `packages/schedule-core` is not optional — that's where the subtle
  bugs live, and it's the code another project will depend on. Include DST-boundary, cross-zone, and
  exception-heavy cases.

## Working in this repo

Development happens through Claude Code, with pull requests reviewed by the repo owner.

- Branch from the default branch; one logical change per PR.
- Describe *what changed and why* in the PR body, and call out anything you were unsure about — the
  owner's review is the design feedback loop, so surface the judgment calls rather than burying them.
- Migrations, generated types, and the code that depends on them belong in the same PR.
- If a change alters visibility semantics, availability math, or time handling, say so explicitly in
  the PR description and update this file or `docs/schema.md` in the same change.

## Open decisions

Not yet settled. Raise them when the work reaches them rather than picking silently:

- Push notifications (Expo push vs. APNs directly) for group messages and plan invites.
- Whether to sync with the iOS system calendar (EventKit), or stay self-contained.
- Whether groups get an explicit "event" object for confirmed plans, or plans are just schedule
  items created from a chosen availability window.
- Free-tier limits: number of groups, message retention.
