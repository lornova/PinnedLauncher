# UI reference — patterns borrowed from other platforms

Design input distilled from three mature launcher/taskbar projects:
[dash-to-panel](https://github.com/home-sweet-gnome/dash-to-panel) (GNOME),
[dash-to-dock](https://github.com/micheleg/dash-to-dock) (GNOME), and KDE Plasma's
[Icons-only Task Manager](https://userbase.kde.org/Plasma/Tasks). Implementations are
irrelevant here (different display stack); the *option surfaces* are what decades of
user feedback produced, and they map cleanly onto our use cases.

> **Scope note (important).** The chosen design uses **native taskbar pins**
> ([ADR-0006](adr/0006-native-taskbar-pins.md)) — we do **not** render the launcher
> buttons. So most patterns below (running indicators, icon geometry, hover animation,
> badges/progress, custom click matrices) are **not ours to implement**: they are
> whatever the Windows taskbar provides, or they are out of scope. This document is
> retained as (a) the rationale for the separation model we require, (b) input for the
> **[management window](management-window.md)** we *do* build, and (c) a menu of ideas
> should a future mode ever render its own UI. Sections are annotated where they no
> longer apply.

## 1. The separation model (validates the core invariant, F-2)

The "launcher never merges with the running window" behavior we require exists in both
references as an explicit mode:

- KDE Icons-only Task Manager: `separateLaunchers: true` (launchers stay a contiguous
  zone at one end) **+** `hideLauncherOnStart: false` (launcher icon stays put when the
  app runs; the running window gets its own separate button). That pair of booleans is
  exactly our model.
- dash-to-panel: `group-apps-use-launchers` — "keep running apps separate from
  favorites".

Under the final design this zone *is* the native pinned area — the separation the
references implement as an option is what native pins give us structurally. Both
references also suggest a subtle **"is running" indicator** on launcher icons; for us
that would require rendering we don't do (see the scope note) — noted, not planned.

## 2. Click matrix (→ UC-2, UC-6, F-9)

All three projects converge on a per-button action matrix. dash-to-dock's compound
`X-or-Y` fallback actions ("focus if single window, previews if many") are the most
user-friendly defaults.

Proposed action enum for us:
`launch-new` · `focus-or-launch` · `cycle-windows` · `minimize-toggle` · `close` · `none`

| Binding | Default (pure launcher) |
|---|---|
| Left click | `launch-new` |
| Middle click | `launch-new` — natively equivalent to left on a launcher-only pin; whether a launch yields a *new instance* is the target's decision (UC-6) |
| Shift+left | `launch-new` natively (UC-6); `focus-or-launch` exists only as the optional per-launcher UC-10 behavior (Could, post-1.0), never as a modifier default |
| Ctrl+Shift+left | — *(the native "elevate the pin" convention is **refused across an elevation boundary**: it would elevate the proxy, a confused-deputy risk — UC-6, ADR-0011; in no-boundary sessions the guard never fires and the click is an ordinary launch. Elevation is a per-launcher feature instead)* |

> **Normative note:** on native pins only the shell's own modifiers exist
> (Ctrl+Shift = elevated); the richer matrix above describes the *optional proxy-side*
> behaviors (`focus-or-launch` is a Could, post-1.0). Click semantics are normatively defined in
> [use-cases.md UC-6](use-cases.md), not here.

Scroll over icon (dash-to-panel `scroll-icon-action`): `none` | `cycle-windows` |
`volume`, with a debounce-ms setting for free-spinning wheels. Could-have.

## 3. Running indicator (stretch; requires window tracking)

dash-to-panel's indicator system, if we ever track running state:
- style: dot / dash / underline / segment-per-window (up to 4 marks);
- edge: top/bottom/left/right; size in px;
- color: fixed, theme, or dominant-color-of-icon;
- separate focused vs unfocused treatment.

MVP ships **without** window tracking (the native taskbar already shows running state);
the indicator is a later option, not a foundation.

## 4. Icon geometry & appearance (→ UC-10, F-10)

Three separate knobs, not one (dash-to-panel: `appicon-margin` vs `appicon-padding`):
- icon size (px),
- inner padding (glyph inset inside the clickable area),
- inter-icon margin (spacing between buttons).

Plus: optional grayscale/monochrome icon mode for a quieter strip; hover feedback
(subtle highlight; animation opt-in, not default).

## 5. Hotkeys (→ UC-14, F-13)

dash-to-panel's proven scheme: modifier+1..0 launches the Nth icon, with a **transient
number overlay** on the icons while the modifier is held (`never` / `while-held` /
`always`). For us: a configurable modifier chord (default off; Win+digit is taken by
the native taskbar).

## 6. Management interactions (→ UC-1, UC-3, UC-4, UC-7)

> Strip-era items below (drag-in to add, drag-reorder, lock strip, strip menu) are
> **N/A under the native-pin design**: adding is the management window's job, ordering
> is native pin drag, and there is no strip to lock. What carried over: the context
> menu content (realized as Jump List tasks) and settings export/import.

- Drag-in to add, drag to reorder, drag-out (or context menu) to remove.
- "Lock strip" toggle preventing accidental drags (dash-to-panel ships this).
- Icon context menu: Open · Run as administrator · Open file location ·
  Properties · Unpin · Move left/right (keyboard-accessible reorder).
- Strip context menu: Add launcher… · Lock strip · Settings · Exit.
- Settings export/import (dash-to-panel ships this; for us: config export/import with
  preview and explicit replace-or-merge — UC-8).

## 7. Badges / progress (explicitly out: F-15)

Unity LauncherAPI-style counter badges and progress bars are two independent toggles in
dash-to-panel. Noted for completeness; **Won't** for this project (no protocol for
Win32 apps to feed us badge data without deep integration).

## 8. Multi-monitor & filtering (→ UC-12, F-12)

- Strip on primary only vs all monitors (dash-to-panel `show-favorites-all-monitors`).
- Per-monitor content filtering exists in the references but adds little for a pure
  launcher strip; not planned.

## 9. KDE extras noted but not adopted

- Audio-playing badge with click-to-mute (`indicateAudioStreams`) — charming, but
  requires per-window audio session tracking; out of scope for a launcher.
- Multi-row strips (`maxStripes`) — taskbar height is fixed on Windows 11; N/A.
