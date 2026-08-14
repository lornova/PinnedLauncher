# ADR-0005 — Overlay strip with tray-flyout fallback (rejected alternative)

- Status: **rejected** — the project excludes any UI drawn on or near the taskbar;
  the launcher mechanism is native taskbar pins
  ([ADR-0006](0006-native-taskbar-pins.md))
- Date: 2026-08-13

## Context

Windows 11 offers no supported way to place third-party launcher buttons *inside* the
taskbar (feasibility study §3). Before native pins were chosen, the leading candidate
was to approximate them from outside: a custom-drawn, topmost **overlay strip**
positioned over the taskbar's free area (the pattern proven for years by ElevenClock
and the dock apps — feasibility §4.2), with a tray-button **flyout panel** as a
fully-supported fallback mode sharing the same core.

## Why it was attractive

- The only non-injecting approach that shows always-visible launcher buttons
  *visually inside* the taskbar row, with full control over icon size, ordering,
  indicators, and menus.
- Its failure mode is cosmetic (misplacement), never a broken shell; the flyout
  fallback keeps the product functional if a Windows update disturbs overlay
  positioning.

## Why it was rejected

Overlay, flyout, and appbar approaches all draw our own UI on or near the taskbar —
excluded outright by the project (requirements non-goals). They also carry a permanent
engineering burden (z-order re-assertion, fullscreen detection, auto-hide tracking,
per-monitor DPI churn, explorer-restart reattachment, taskbar geometry shifts) and
still only *imitate* the taskbar. Native pins (ADR-0006) provide the real thing —
OS-rendered, OS-persisted, user-draggable — at the cost of one pin gesture per
launcher.

## Consequences

- The overlay analysis survives in the feasibility study (§4–§5) as evidence; it is
  the documented plan-B family should the pin mechanism ever become untenable.
- No product code path depends on custom taskbar-adjacent rendering, which is what
  keeps the stack free of GPU/z-order/shell-geometry machinery (ADR-0004).
