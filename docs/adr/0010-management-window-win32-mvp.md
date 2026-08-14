# ADR-0010 — Management window: plain Win32 + common controls, MVP split

- Status: accepted
- Date: 2026-08-13
- Related: [ADR-0004](0004-cpp-win32-stack.md) — language/stack this UI builds on
- Design: [management-window.md](../management-window.md)

## Context

The management window is the project's only built UI (pins and jump lists are
OS-drawn). Its functional surface is small: a list of launchers, an add/edit dialog, a
guided pin dialog, and a short settings page. Candidates: plain Win32 with common
controls; a custom-drawn Direct2D window; WinUI 3 via C++/WinRT (admissible per C-1
only if plain Windows APIs are insufficient).

## Decision

**Plain Win32 top-level window with common controls** (ListView, buttons,
`TaskDialogIndirect`), structured as **Model–View–Presenter**:

- **Presenters** (`LauncherListPresenter`, `EditPresenter`, `PinGuidePresenter`) hold
  all logic, depend only on the Q-6 core interfaces, and are fully unit-tested
  (fakes / trompeloeil) — this is how the only UI module meets Q-4 coverage.
- **Views** are logic-free Win32 glue (message → presenter call → render state), listed
  in the named coverage exclusions. A small `Window` RAII base class with message-map
  virtuals is the natural inheritance use here (Q-2); presenters get no artificial base
  (Q-3).
- **Single instance** via named mutex + `WM_COPYDATA` argument forwarding, so
  jump-list tasks (`--edit`, `--add`, `--remove`) always land in one window.

**Theming policy — documented APIs only**: dark title bar via
`DwmSetWindowAttribute(DWMWA_USE_IMMERSIVE_DARK_MODE)`; per-control colors only where
documented (`LVM_SETBKCOLOR`, custom-draw). **No undocumented uxtheme ordinals**
(SetPreferredAppMode-style hacks) — same principle as ADR-0003: no fragile internals.
Consequence accepted: on a dark system theme the client area stays light-ish in MVP; a
fuller documented-API dark treatment is a *Could*.

Rejected:
- **Custom Direct2D window** — overdesign (Q-3): would hand-roll list rendering, text
  editing, and a UIA provider that common controls provide for free, to restyle a
  config dialog nobody keeps open.
- **WinUI 3** — the C-1 gate is not met: nothing in the surface exceeds common
  controls. It would add the Windows App SDK runtime and packaging pressure purely for
  cosmetics, and weaken the "single self-contained exe" property (NF-1 spirit).

## Consequences

- Accessibility (UIA, keyboard, high-contrast, IME) inherited from common controls —
  NF-10 nearly free.
- The window is **fully QT-automatable via UI Automation** (no user gestures): launch
  with args, drive the dialogs, assert artifacts on disk (ADR-0009 `[qt]` tier).
- Imperfect dark mode is a known, accepted trade-off, revisitable only if Microsoft
  ships documented Win32 dark theming (or the C-1 WinUI gate is ever genuinely met).
