# ADR-0006 — Native taskbar pins (AUMID proxy shortcuts) as the launcher mechanism

- Status: **accepted — conditional on spike S-3** (the go/no-go); to be annotated with
  verification evidence before phase P1 starts, or superseded if S-3 fails
- Amended 2026-08-15: S-3 verified the mechanism on build family 26200 (Pro,
  26200.8875) — flavor-B cases pass for plain-Win32, self-AUMID, and packaged
  targets; **GO recorded**, see
  [docs/spikes/s3-aumid.md](../spikes/s3-aumid.md) §7. Finding: flavor-A pins to
  plain Win32 exes merge via **target-path association** (every instance of the
  target exe, however launched) → flavor B mandatory for that target class.
  Families 26100/28000 remain as non-blocking confirmation runs; 22631 descoped
  (out of support 2026-11-10).
- Amended 2026-08-15: S-8 resolved the one-time-pin cost — from the unpackaged
  helper assuming the launcher's AUMID, `RequestPinCurrentAppAsync` pins the
  generated Start entry via one consent dialog, and the landed pin is equivalent
  to a gesture pin (S-4 + S-9 oracles); `RequestPinAppListEntryAsync` and the
  secondary-tile APIs are closed to unpackaged callers (`0x8000000E`). The flow
  is **API-first with the gesture as fallback**, posture user-configurable — see
  [docs/spikes/s8-pinapi.md](../spikes/s8-pinapi.md) §7.
- Date: 2026-08-13
- Related: [ADR-0005](0005-overlay-strip-with-flyout-fallback.md) — the rejected
  overlay/flyout alternative

## Context

The requirement is launchers that (a) are real pinned taskbar buttons wearing the
target's icon and name, (b) launch the target on click, (c) never expand in place, and
(d) sit in the pinned-app zone (after Start/Search, left of the running apps). The
project excludes any approach that draws its own window on or near the taskbar
(overlay, flyout, appbar — ADR-0005) as well as injection/reparenting into
`explorer.exe` (ADR-0003).

Native taskbar pinning is keyed on AppUserModelID (AUMID), not on the executable path
([Microsoft `appids` documentation](https://learn.microsoft.com/windows/win32/shell/appids)).
This is the only mechanism that meets every requirement above using supported APIs.

## Decision

Each launcher is a **proxy shortcut** (`.lnk`) with:
- the **target's icon and name**,
- an **explicit, distinct AUMID** (`PinnedLauncher.Proxy.<slug>`) set via `IPropertyStore`
  before pinning.

Clicking the pin launches the target — either directly (flavor A) or via a **windowless
proxy exe** (flavor B, recommended, for per-launch control and to decouple the target's
launch from the pin's shortcut identity). The target lands under its **own** AUMID —
its explicit one, or a system-computed identity — and therefore appears as a
**separate** taskbar button; the pin never expands in place (expected behavior, **to
be verified** by S-3; see architecture §2). Placement is
native and user-draggable. No overlay, flyout, appbar, reparenting, or injection.

## Consequences

- **Positive:** nothing is drawn over the taskbar; there is no shell-geometry/z-order
  monitor and no custom renderer. The OS owns rendering, placement, DPI, theme, and
  resilience across explorer restarts. Placement is exactly the requested zone and stays
  user-controlled.
- **Cost:** a **one-time manual "Pin to taskbar"** per launcher — no API pins another
  app *silently*; `TaskbarManager`'s consent-gated request APIs (incl.
  `RequestPinAppListEntryAsync`, which accepts a specified app-list entry) are
  evaluated in spike S-8 and may replace the gesture.
- **Risk:** AUMID non-merge and identity propagation must be confirmed on every
  supported build family (C-2) (**spike S-3**). If a target picks up the pin's shortcut identity it could
  merge into the pin; flavor B — a windowless proxy that decouples the target's launch
  from the pin's shortcut context — mitigates this. No documented API can set another
  process's AUMID, so decoupling is an expected behavior to verify, not a guarantee
  (architecture §2).
- The only GUI the project builds is an ordinary management/settings window; heavy custom
  rendering is unnecessary ([ADR-0004](0004-cpp-win32-stack.md)).
- Right-side/notification-area placement is deliberately **not** pursued: the pinned zone
  is the desired location, and the far right is unreachable natively anyway.
