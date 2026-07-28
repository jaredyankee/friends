# schedule-core

Design for the portable scheduling engine: zone-correct recurrence expansion, free/busy derivation,
and multi-participant availability, with no knowledge of where calendar data comes from.

This is a design document. Nothing is implemented yet.

## Why a package

Friends needs this logic. So does the owner's other calendar app, which draws from different sources.
The logic is identical in both cases; only the data plumbing differs. Extracting it means one
well-tested implementation of the part that's easy to get wrong, rather than two divergent ones.

### What already exists, and what we're actually adding

| Library | Does | Verdict |
| --- | --- | --- |
| `rrule` | RFC 5545 recurrence expansion | **Use it.** Don't rebuild recurrence parsing. Its zone handling needs wrapping (below), not replacing. |
| `luxon` | IANA zone math, DST-aware arithmetic | **Use it.** |
| `rschedule` | Recurrence *and* set algebra over occurrence streams | Closest prior art, and genuinely well-designed — but effectively unmaintained for years. Not a dependency worth taking. |
| `ical.js` / `node-ical` | ICS parsing | Adapter-layer concern, not core. Relevant if the other app ingests ICS feeds. |
| `date-fns`, `@internationalized/date` | Date primitives | No recurrence, no availability. |
| Cal.com availability | Multi-participant availability | Good logic, not extractable as a package. |

**The gap:** nothing gives you zone-correct recurrence *plus* multi-participant free/busy
intersection behind a pluggable source interface. That's what this package is, and it should stay
that thin. If a feature can be done by composing `rrule` and `luxon` directly at the call site, it
probably doesn't belong here.

## Design principles

1. **No I/O in the core.** Every function is pure. Fetching is the caller's job, behind
   `ScheduleSource`. This is what makes the package testable and portable.
2. **Plain serializable data at every boundary.** ISO 8601 strings, not `Date` objects. Data crosses
   HTTP, RPC, and process boundaries unchanged, and golden test fixtures are plain JSON that a
   non-TypeScript implementation could reuse.
3. **Zero app dependencies.** No Supabase, React, Expo, or app-domain concepts. Two runtime
   dependencies: `rrule` and `luxon`.
4. **Borrow iCalendar vocabulary.** `transparency`, `occurrenceStart`, `RRULE`. Following RFC 5545
   where it fits means ICS and CaldAV adapters are a small step later, and it avoids inventing terms.
5. **App semantics stay in the app.** The core has no idea what a "group" or a "visibility level" is.
   See "Proving the boundary" below.

## Core types

```ts
/** ISO 8601 instant, always UTC at rest. "2026-03-08T14:00:00.000Z" */
export type Instant = string;

/** IANA zone identifier. "America/New_York" */
export type TimeZone = string;

export interface Interval {
  start: Instant;
  end: Instant;
}

/**
 * RFC 5545 TRANSP. Opaque events consume time and block availability;
 * transparent ones appear on a calendar without blocking anything.
 */
export type Transparency = 'opaque' | 'transparent';

export interface RecurrenceRule {
  /** RFC 5545 RRULE body, without the "RRULE:" prefix. */
  rrule: string;
  /** Hard bound for expansion. Must agree with any UNTIL/COUNT inside rrule. */
  until?: Instant;
  exceptions?: RecurrenceException[];
}

/**
 * A deviation from the rule for one instance. Keyed by the instant the rule
 * *would have* produced, which stays stable even when the instance moves.
 */
export interface RecurrenceException {
  occurrenceStart: Instant;
  cancelled?: boolean;
  /** Overrides. Omitted fields inherit from the parent event. */
  start?: Instant;
  end?: Instant;
  metadata?: unknown;
}

/**
 * One entry on someone's calendar, recurring or not.
 * M is app-defined payload the core never reads — title, colour, location.
 */
export interface CalendarEvent<M = unknown> {
  id: string;
  /** Which ScheduleSource produced this. */
  sourceId: string;
  /** Whose calendar this sits on — a person, room, or any schedulable entity. */
  subjectId: string;
  start: Instant;
  end: Instant;
  /** Zone the event was authored in. Recurrence expands against this. */
  timeZone: TimeZone;
  allDay?: boolean;
  transparency: Transparency;
  recurrence?: RecurrenceRule;
  metadata?: M;
}

/** A single materialized instance. Never persisted by the core. */
export interface Occurrence<M = unknown> {
  eventId: string;
  sourceId: string;
  subjectId: string;
  start: Instant;
  end: Instant;
  /** The rule-generated start, before any exception moved it. */
  occurrenceStart: Instant;
  transparency: Transparency;
  metadata?: M;
}

export interface FreeBusy {
  subjectId: string;
  /** Normalized: sorted, non-overlapping, clipped to the queried range. */
  busy: Interval[];
}

export interface AvailabilityWindow {
  start: Instant;
  end: Instant;
  freeSubjectIds: string[];
  busySubjectIds: string[];
  /** True when freeSubjectIds covers every subject in the query. */
  allFree: boolean;
}
```

`subjectId` rather than `userId` is deliberate: it lets the same engine schedule rooms, equipment, or
any other bookable thing without a rename. Costs nothing now, saves a breaking change later.

## Source adapters

The only extension point, and the reason the package transfers between apps.

```ts
export interface EventQuery {
  subjectIds: string[];
  range: Interval;
}

export interface SourceCapabilities {
  /** False if the source pre-expands recurrence and never returns rules. */
  recurrence: boolean;
  writable: boolean;
}

export interface ScheduleSource<M = unknown> {
  readonly id: string;
  readonly capabilities: SourceCapabilities;
  fetchEvents(query: EventQuery): Promise<CalendarEvent<M>[]>;
}

/** Fan out across sources, merge results. Failures are reported, not thrown. */
export function createResolver<M>(sources: ScheduleSource<M>[]): {
  fetchEvents(query: EventQuery): Promise<{
    events: CalendarEvent<M>[];
    failures: { sourceId: string; error: Error }[];
  }>;
};
```

Partial failure is surfaced rather than thrown: one dead feed shouldn't blank out a calendar. The
caller decides whether to render what it has with a warning, or treat it as fatal.

## Functions

```ts
// --- interval algebra (calendar-agnostic) ---
export function normalize(intervals: Interval[]): Interval[];   // sort + merge overlaps
export function union(a: Interval[], b: Interval[]): Interval[];
export function intersect(a: Interval[], b: Interval[]): Interval[];
export function subtract(from: Interval[], minus: Interval[]): Interval[];
export function clip(intervals: Interval[], range: Interval): Interval[];

// --- recurrence ---
export function expandEvent<M>(
  event: CalendarEvent<M>,
  range: Interval,
  options?: { maxOccurrences?: number },
): Occurrence<M>[];

export function expandEvents<M>(events: CalendarEvent<M>[], range: Interval): Occurrence<M>[];

// --- free/busy + availability ---
export function toFreeBusy(occurrences: Occurrence[], range: Interval): FreeBusy[];

export function computeAvailability(
  freeBusy: FreeBusy[],
  range: Interval,
  options?: AvailabilityOptions,
): AvailabilityWindow[];

export interface AvailabilityOptions {
  /** Drop windows shorter than this. Default 0. */
  minDurationMinutes?: number;
  /** Snap boundaries outward to a grid, e.g. 15. Default: no snapping. */
  granularityMinutes?: number;
  /** Only return windows where at least this many subjects are free. */
  quorum?: number;
  /** Constrain results to these spans, e.g. waking hours. */
  within?: Interval[];
}
```

`expandEvent` caps at `maxOccurrences` (default 1000) and throws past it rather than hanging — an
unbounded `RRULE` with a wide range is otherwise an easy way to lock a thread.

## Zone-correct expansion

The single hardest thing this package does, and the reason it exists.

`rrule` expands in UTC or in floating local time. Neither is what a calendar needs. "Every weekday at
9am" must stay at 9am local across a DST boundary; expanding in UTC silently shifts every occurrence
by an hour for half the year.

The wrapping algorithm:

1. Convert the event's `start` into `timeZone` to get the local wall-clock anchor.
2. Expand the rule against that anchor as **floating** local time — dates and times with no offset.
3. Convert each generated local start back to UTC *in `timeZone`*, resolving DST at that moment.
4. Carry duration from the parent (`end - start`) unless an exception overrides it.
5. Apply exceptions by `occurrenceStart`: drop cancelled, patch the rest.
6. Clip to the requested range.

Ambiguous and nonexistent local times get explicit policy rather than whatever the library defaults
to. Spring-forward gaps (2:30am on a day that has no 2:30am) shift forward to the first valid
instant; fall-back repeats (2:30am occurring twice) resolve to the first. Both are documented,
tested, and configurable if a caller needs the other choice.

All-day events are local-midnight to local-midnight in the event's zone — not a separate date type,
and not a UTC-midnight approximation that drifts a day for anyone east or west.

## Test fixtures

`test/fixtures/` holds golden cases as plain JSON: input events, a range, expected occurrences.
Plain data so the same suite can validate a server-side implementation in another language, and so a
failure reads as a diff rather than a stack trace.

Mandatory coverage before the package is trusted:

- Spring-forward and fall-back boundaries, in both hemispheres.
- An event authored in one zone, queried by a viewer in another.
- Recurring events with cancelled instances, moved instances, and both at once.
- Zones with non-hour offsets (`Asia/Kathmandu`, `Australia/Eucla`).
- A recurring event whose anchor predates the query range by years.
- Back-to-back and exactly-abutting intervals — the classic off-by-one in `subtract`.

## Proving the boundary

Friends' visibility model is the test of whether the core is genuinely app-agnostic. It is, and here's
the mapping:

| Friends concept | Where it lives | How it reaches the core |
| --- | --- | --- |
| `hidden` for this viewer | Postgres RLS | Row never returned. The core never sees it, so the owner reads as free — which is the intended product behavior. |
| `busy` for this viewer | `visible_schedule_items` view | `transparency: 'opaque'`, `metadata` with title/location stripped. |
| `details` for this viewer | `visible_schedule_items` view | `transparency: 'opaque'`, `metadata` populated. |
| Groups, friendships | Postgres | Resolved to a `subjectIds` list before the query. Core never hears the words. |

The entire visibility system collapses into "which rows, and how much metadata" — both settled before
the core is called. The other app substitutes its own rules at the same seam. If a future feature
can't be expressed this way, that's the signal the boundary needs rethinking, not that the core needs
an app-specific escape hatch.

## Availability API contract

Both apps should expose availability identically, so a client written against one works against the
other. Request:

```jsonc
{
  "subjectIds": ["...", "..."],
  "range": { "start": "2026-08-01T00:00:00.000Z", "end": "2026-08-08T00:00:00.000Z" },
  "options": { "minDurationMinutes": 30, "granularityMinutes": 15 }
}
```

Response is `AvailabilityWindow[]` verbatim — the same shape the library returns, no transport-specific
envelope. In Friends this is the `group_availability` RPC described in `docs/schema.md`; the SQL
implementation and the TypeScript one must agree, and the shared fixtures are how that's enforced.

## Packaging

- **Working name:** `schedule-core`. Publishing name is the owner's call — a neutral scope
  (`@jaredyankee/schedule-core`) keeps it usable from the other app without Friends branding.
- **Lives in this repo** under `packages/schedule-core`, via npm workspaces, until the API settles.
  Iterating in-tree avoids version churn while the shape is still moving. Extract to its own repo once
  the other app consumes it for real.
- **Consuming it before extraction:** the other app can install straight from the Git URL and
  subpath — no publish step needed to start.
- **Semver, strictly**, from the first release. The public surface is a contract the moment a second
  project depends on it.
- **Expo caveat, worth knowing up front:** a workspace package needs `metro.config.js` adjustments —
  `watchFolders` covering the package directory and `nodeModulesPaths` resolving up to the root. Small
  and well-documented, but it's real setup, not free.

## Open questions

- **Working hours / recurring availability rules.** "I'm never free before 9am" is a rule about
  *availability*, not an event. Does it belong in the core as a first-class concept, or does the app
  synthesize blocking events for it? Leaning app-side for v1 to keep the core thin, via the `within`
  option.
- **Buffers and travel time.** "15 minutes either side of anything at an address" is a real
  scheduling feature and a natural fit here — but it's scope. Not v1.
- **Write path.** `capabilities.writable` is in the interface but nothing uses it. Leave the door open,
  don't build it until the other app needs to push events back to a source.
- **Occurrence caching.** On-demand expansion should be fast enough at Friends' scale. Measure before
  adding a cache; a cache reintroduces exactly the invalidation problems this design avoids.
