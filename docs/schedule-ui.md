# schedule-ui

Design for the React Native calendar component kit: views, gestures, layout math, and theming — the
pieces you drop into a screen. Consumes `schedule-core` for all date and availability logic.

This is a design document. Nothing is implemented yet.

## Why this is a second package, not one

`schedule-core` must stay importable from places React cannot go: Supabase Edge Functions, the SQL
availability path, any server-side or non-RN consumer. Bundling components into it would make
server-side availability pull in React Native.

So: two packages, published together, versioned in lockstep.

```
schedule-core   →  dates, recurrence, free/busy, availability.  deps: rrule, luxon
schedule-ui     →  components, gestures, layout.                deps: schedule-core
                                                                peers: react, react-native,
                                                                       reanimated, gesture-handler
```

Apps install both. Nothing in `schedule-ui` reaches around core to reimplement date math, and nothing
in core knows a view exists.

## Build vs. wrap

The surveyed libraries (`@howljs/calendar-kit`, `react-native-calendars`, `react-native-big-calendar`)
each solve part of this. None models multi-participant availability, which is the piece Friends needs
most and the piece with no off-the-shelf answer.

**The rule that keeps this decision reversible:** our component API is the contract; whatever renders
the time grid underneath is an implementation detail. If `WeekView` wraps `calendar-kit` in v1 and a
hand-rolled Reanimated grid in v3, consumers should not notice. That means no third-party prop shapes
leak through our public API, ever — no spreading `...rest` into a vendor component, no re-exporting
their types.

Recommended split for v1, pending the owner's call:

| Surface | Approach |
| --- | --- |
| Week / Day time grid | Wrap `@howljs/calendar-kit`. Rebuilding a performant, gesture-driven, virtualized time grid is weeks of work it has already done. |
| Month grid | Build. It's a straightforward layout, and owning it avoids the styling limitations that make the Wix library painful. |
| Agenda list | Build on FlashList. Trivial next to the grid, and needs custom empty/availability states. |
| Availability heatmap + "who's free" | Build. Nothing to wrap. This is the differentiated surface. |

## Two layers

The package ships headless hooks *and* components built on them. Consumers pick a level.

- **Hooks** give layout math and interaction state, with zero opinions about appearance. This is what
  makes the kit genuinely transferable — an app with a completely different visual language uses the
  overlap-packing and drag logic without inheriting our look.
- **Components** are the batteries-included layer, themed, ready to drop in.

Friends uses the components. Another app with strong existing design can drop to the hooks. If a
component can't be expressed as `hook + presentation`, that's a smell worth fixing.

## Components

```tsx
<CalendarProvider
  theme={theme}            // required — see Theming
  timeZone="America/New_York"
  weekStartsOn={0}
  locale="en-US"
  hourHeight={64}
>
```

Wraps a subtree, supplies theme and display zone. Every component below must be rendered inside it.

```tsx
<MonthView
  occurrences={Occurrence[]}
  cursor={Instant}                        // month containing this instant
  onCursorChange={(next: Instant) => void}
  onSelectDate={(date: Instant) => void}
  renderDayIndicator={(day) => ReactNode}  // dots, density bars, availability tint
/>

<WeekView
  occurrences={Occurrence[]}
  cursor={Instant}
  availability={AvailabilityWindow[]}     // optional background layer
  onOccurrencePress={(o: Occurrence) => void}
  onCreate={(draft: Interval) => void}     // drag on empty space
  onMove={(o: Occurrence, next: Interval) => void}
  onResize={(o: Occurrence, next: Interval) => void}
  renderOccurrence={(o, layout) => ReactNode}
/>

<DayView {...same as WeekView} />

<AgendaList
  occurrences={Occurrence[]}
  range={Interval}
  onOccurrencePress={(o) => void}
  renderSectionHeader={(date) => ReactNode}
  ListEmptyComponent={ReactNode}
/>

<AvailabilityStrip
  windows={AvailabilityWindow[]}
  range={Interval}
  onWindowPress={(w: AvailabilityWindow) => void}
/>

<GroupAvailabilityView
  windows={AvailabilityWindow[]}
  subjects={{ id: string; label: string; avatarUrl?: string }[]}
  cursor={Instant}
  onWindowPress={(w) => void}              // drives the "who's free" sheet
  highlightAllFree                          // emphasize windows where everyone is free
/>
```

**Components never fetch.** They take `occurrences` and `availability` as props. Data loading,
caching, and auth belong to the app. This is the same discipline as core's no-I/O rule, and it's what
lets the kit work against any backend.

## Hooks

```ts
// Layout: pack concurrent occurrences into lanes. The fiddly part of any time grid.
useTimeGridLayout(args: {
  occurrences: Occurrence[];
  range: Interval;
  hourHeight: number;
  timeZone: TimeZone;
}): PositionedOccurrence[];

interface PositionedOccurrence {
  occurrence: Occurrence;
  top: number; height: number;
  lane: number; laneCount: number;   // horizontal packing for overlaps
}

// Navigation cursor, controlled or uncontrolled.
useCalendarCursor(args?: { initial?: Instant; view?: 'month' | 'week' | 'day' }): {
  cursor: Instant;
  view: 'month' | 'week' | 'day';
  goToNext(): void; goToPrevious(): void; goToToday(): void;
  setCursor(i: Instant): void; setView(v): void;
};

// Current-time line. Ticks on an interval, cleans itself up.
useNowIndicator(timeZone: TimeZone): { offsetY: number; isVisible: boolean };

// Drag-to-create / move / resize. Returns Reanimated gesture handlers.
useDragInteraction(args: {
  hourHeight: number;
  snapMinutes?: number;               // default 15
  onCommit(interval: Interval): void;
}): { gesture: GestureType; draft: SharedValue<Interval | null> };

// Binds core availability into render-ready bands.
useAvailabilityLayout(args: {
  windows: AvailabilityWindow[];
  range: Interval;
  hourHeight: number;
}): { top: number; height: number; state: 'free' | 'partial' | 'busy'; window: AvailabilityWindow }[];
```

Overlap packing (`useTimeGridLayout`) is the single most reusable thing here. Every calendar needs it,
it's easy to get subtly wrong, and it has nothing to do with visual design.

## Theming

The kit has **no hard-coded colors**. `CalendarProvider` requires a theme object, and every visual
token resolves from it. This serves two masters at once: Friends' user-selectable palettes with
light/dark, and another app's entirely different design language.

```ts
export interface CalendarTheme {
  colors: {
    background: string;
    surface: string;
    border: string;
    text: string;
    textMuted: string;

    primary: string;
    onPrimary: string;          // text over primary — Friends' white/inverted rule

    free: string;               // availability states, must differ by more than hue
    partiallyFree: string;
    busy: string;

    nowIndicator: string;
    occurrence: Record<string, string>;   // keyed by CalendarEvent color_key
  };
  spacing: { xs: number; sm: number; md: number; lg: number };
  radii:   { sm: number; md: number; lg: number };
  typography: {
    label: TextStyle; body: TextStyle; caption: TextStyle;
  };
}
```

Rules:

- A literal color anywhere in `schedule-ui` is a bug. It will not follow the user's palette or their
  light/dark setting.
- Availability states must stay distinguishable without relying on hue — pattern, opacity, or border
  weight alongside color. Roughly 1 in 12 men has some color vision deficiency, and free-versus-busy
  is the one distinction this app cannot afford to lose.
- The kit ships a default theme so it renders sensibly out of the box. Friends overrides it from the
  app's palette tokens.

## Performance

A calendar is a scroll-and-drag surface; jank is immediately obvious. Non-negotiables:

- **Gestures run on the UI thread** via Reanimated worklets. No JS-thread state update per frame
  during a drag — the draft interval lives in a `SharedValue` and only commits to React state on
  release.
- **Virtualize long ranges.** Month and agenda views render windows, not years.
- **Layout math is memoized** on `(occurrences, range, hourHeight)`. `useTimeGridLayout` is O(n log n)
  and must not rerun on unrelated renders.
- **Occurrence expansion happens outside render.** Call `schedule-core` in a query layer, pass results
  down. Expanding a recurrence rule inside a component body is a performance bug and a correctness
  hazard.

Benchmark target: a week view holding 200 occurrences scrolls and drags at 60fps on an iPhone 12.

## Accessibility

Weaker in every surveyed library than it should be, and cheap to get right from the start:

- Every occurrence block exposes an accessibility label with title (when visible), start, and end in
  readable form — not "2 to 3", but "Work, 2:00 PM to 3:00 PM".
- Availability windows announce their state and participant count.
- Respect Dynamic Type; the time grid scales with text size rather than clipping.
- Hit targets meet 44×44pt, including resize handles.
- Drag interactions have a non-gesture fallback — long-press menu or an edit form. A calendar that can
  only be operated by dragging is unusable with assistive tech.

## Testing

- **Layout math is unit-tested** with plain data, no rendering. Overlap packing, lane assignment, and
  DST-boundary positioning are pure functions and deserve golden fixtures like core's.
- **Components get render tests** via `@testing-library/react-native` for prop-to-output behavior and
  accessibility labels.
- **Gestures get integration tests** where practical, acknowledging RN gesture testing is awkward. The
  fallback is keeping gesture logic thin and pushing decisions into testable pure functions.

## Open questions

- **Wrap or build the time grid.** The table above recommends wrapping `calendar-kit` for week/day.
  This is the biggest single decision in the kit — worth a spike before committing, since it shapes
  how much of the drag and virtualization work we own.
- **Does the other app need month/agenda at all,** or only timeline views? Changes what ships in v1.
- **Web support.** `react-native-web` would make the kit usable from a browser, at the cost of
  constraining gesture implementation. Not v1 unless there's a known need.
- **Recurring-event editing UI** ("this event / this and following / all events") is a genuinely hard
  interaction pattern and a natural fit for the kit. Deferred, but the exceptions model in core
  already supports it.
