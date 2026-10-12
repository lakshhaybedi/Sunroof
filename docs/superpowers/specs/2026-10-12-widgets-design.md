# Sunroof Widgets — Design Spec

Date: 2026-10-12 · Author: Lakshhay Bedi · Status: draft for review

## 1. Goal

A widget area in the shelf with five v1 widgets — **Calendar, Tasks, Music, Weather, System Stats** — laid out on a snap grid the user arranges. Widgets must keep Sunroof's performance budget: with the shelf closed, no widget does any work.

### Success criteria
- Default first-run layout appears and every widget works (or shows a clear "Grant access" state).
- Widgets can be added, removed, resized and dragged; nothing overlaps; layout persists per display.
- Shelf closed: idle CPU ~0 %, 0 idle wake-ups, memory budget unchanged (≤ 80 MB closed, ≤ 150 MB open).

### Non-goals (v1)
In-widget event editing, playlists/queues, weather alerts/radar, hosting other apps' WidgetKit widgets (no public API), any "now playing" beyond Apple Music and Spotify (no public API), further widgets (clock, timer, quick links, per-process stats).

## 2. Widget area

- A band along the **bottom of the shelf**, under the columns. On by default; its height is dragged from its top edge (rows of ~150 pt) and it can be hidden (Settings › Widgets and a header toggle).
- **Snap grid**: square cells ≈ 150 pt; column count = floor(band width / cell). Sizes **small 1×1**, **medium 2×1**, **large 2×2**.
- **Drag** to move; other widgets reflow to make room; never overlap. **Right-click**: size ▸ (allowed sizes only), Settings…, Remove. A **＋** tile opens a gallery of widgets not yet placed (each widget at most once in v1).
- Layout saved **per display** (like column widths). When the band gets narrower/shorter, widgets reflow in reading order; ones that don't fit are kept in the layout and reappear when there's room.
- **Default layout** (band two rows tall): Calendar (L), Weather (M), Music (M), Tasks (M), System Stats (S).

## 3. Architecture

- `protocol SunroofWidget` — `id`, `name`, `symbol`, `allowedSizes`, `defaultSize`, `@ViewBuilder func view(size:)`, optional `settingsView`, `start()` / `stop()`.
- `WidgetGrid` — pure value type: placement, snapping, collision resolution, reflow on resize, add/remove/resize. Fully unit-tested.
- `WidgetLayoutStore` — persists `[displayKey: [Placement]]` (widget id, origin, size) in `UserDefaults`.
- `WidgetHost` — owns widget instances; `start()` all on shelf show, `stop()` all on hide (hooks into `ShelfController.onShow/onHide`).
- **Permissions** are requested only when a widget that needs them is added or first shown: Calendar & Reminders (EventKit), Location (Weather, optional), Apple Events (Music / Spotify). Info.plist gains the matching usage strings.
- Each widget's data model is a small `@Observable` class with a pure, tested core (parsing, formatting, merging).

## 4. Widgets

### 4.1 Calendar (EventKit · M / L · default L, **month view**)
- **Large**: month grid; today ringed in the accent colour; dots for days with events (calendar colours); below it the selected day's agenda (time, title, colour). ‹ › change month; clicking a day selects it.
- **Medium**: compact month grid, or (toggle) next 3 events.
- Clicking an event opens it in Calendar; ＋ opens Calendar.app at the selected day (no in-widget editor).
- Live via `EKEventStoreChanged`. Settings: calendars shown, first weekday (default: system).

### 4.2 Tasks (M / L)
- **Sources**: Apple Reminders (EventKit, two-way) when access is granted; otherwise — or if chosen — Sunroof's own list stored in `Notes/Tasks.md` as markdown checkboxes (it is also a normal note).
- Header list picker (Reminders lists + "Sunroof"). Tick to complete; inline "+ Add a task" (⏎ adds); due dates shown, overdue in red. Large adds Today / Scheduled filters. Completed items fade out after a moment.
- Live via `EKEventStoreChanged` or the Notes folder watcher.

### 4.3 Music (S / M)
- **Apple Music and Spotify** via their scripting interfaces; shows whichever is playing (most recently started wins).
- Medium: artwork, title, artist, progress, ⏮ ⏯ ⏭. Small: artwork, ⏯ on hover.
- Track changes from `com.apple.Music.playerInfo` / `com.spotify.client.PlaybackStateChanged` distributed notifications (no polling); progress advances locally while visible.
- "Not playing" state with buttons to open Music / Spotify. One-time Apple Events prompt per app.

### 4.4 Weather (Open-Meteo · S / M / L)
- Small: temperature, condition, high/low. Medium: + next 6 hours. Large: + 5-day forecast.
- Location: a searched city (default; Open-Meteo geocoding) or "Use my location" (CoreLocation, asks permission). °C/°F from the system locale.
- Refresh every 30 min while the shelf is open; last result cached for offline.

### 4.5 System Stats (S / M)
- Small: CPU and memory rings. Medium: CPU, memory, battery (charge state), free disk, network ↑/↓.
- 1 s refresh only while visible; public APIs only (`host_statistics`, `IOPowerSources`, `URLResourceValues`, `getifaddrs`); no permissions.

## 5. Settings

New **Widgets** tab: show widget area, row count, per-widget settings (calendars, first weekday, task source/list, weather location & units override), "Reset layout".

## 6. Testing

Unit tests: `WidgetGrid` (snap, collisions, reflow, resize, add/remove, persistence round-trip), Tasks.md parsing/writing, task-source selection, weather response parsing and unit formatting, music state merging (two players), stats formatting, calendar month-grid generation (first weekday, leading/trailing days, event-dot mapping). Manual checklist for permissions, live updates and drag interactions. Perf check (shelf closed vs open) against the budget.

## 7. Build order

One implementation plan, tasks in order: grid + layout store → widget area UI (band, drag, gallery, context menu) → System Stats → Calendar → Tasks → Weather → Music → Settings tab → checklist & perf.
