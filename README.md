# PinnedLauncher

A native Windows 11 quick-launch replacement built on **real taskbar pins**. Each
launcher is a pinned button that wears the target application's icon and name — plus a
small corner **launcher badge** (in the spirit of the shortcut-arrow overlay) — and
launches the target when clicked. Thanks to a distinct AppUserModelID, the pin **never
expands in place**: the running application opens as its **own separate taskbar
button**, leaving the launcher untouched. Right-clicking a launcher pin opens its own
menu (Jump List tasks: change name or icon, add a new launcher, remove).

The pins live where pins natively live — after Start/Search, left of the running-app
buttons — and the user drags them into any order. Nothing is drawn on or near the
taskbar: no overlay window, no flyout, no injection into `explorer.exe`. This fixes the
one thing wrong with the Windows 11 pinned-apps model (a pinned icon morphing into the
running window) while keeping everything native.

## Status

**Feasibility study complete; architecture selected conditionally — implementation
planning.** The chosen design (ADR-0006) is accepted **subject to validation spike
S-3**, the go/no-go that must pass before implementation starts. No code yet. Open source
(license TBD before the first public tag); releases will follow the
[release plan](docs/release-plan.md): 0.1–0.7 alphas → 0.8.x beta (feature freeze) →
0.9.x release candidates (bug fixes only) → the last RC promoted to **1.0** (same
source commit, rebuilt only to stamp the new version).
Work tracking: [TODO.md](TODO.md) · phasing:
[implementation plan](docs/implementation-plan.md).

| Document | Content |
|---|---|
| [docs/feasibility.md](docs/feasibility.md) | Platform constraints, prior art, technique assessment, conclusion |
| [docs/use-cases.md](docs/use-cases.md) | Actors and use cases |
| [docs/requirements.md](docs/requirements.md) | Functional / non-functional requirements and constraints |
| [docs/architecture.md](docs/architecture.md) | Alternative designs, trade-off matrix, recommended path |
| [docs/management-window.md](docs/management-window.md) | Design of the management window (the app's only UI) |
| [docs/ui-reference.md](docs/ui-reference.md) | UI patterns borrowed from dash-to-panel / dash-to-dock / KDE |
| [docs/release-plan.md](docs/release-plan.md) | Version scheme, stages (alpha/beta/RC), gates to 1.0 |
| [docs/implementation-plan.md](docs/implementation-plan.md) | Phases P0–P3 and the release train 0.1 → 1.0 |
| [TODO.md](TODO.md) | Items before 1.0 / after 1.0 |
| [docs/adr/](docs/adr/) | Architecture Decision Records |

## Feasibility verdict (TL;DR)

Feasible, on documented shell APIs only (`IShellLink`, `IPropertyStore`,
`IShellItemImageFactory`, `ICustomDestinationList`, `ShellExecuteEx`). Taskbar identity
and grouping are keyed on AppUserModelID, which is what makes the never-expand-in-place
behavior possible; the badge is baked into the generated icon; the per-launcher menu is
the pin's Jump List, which works with no process running.

Alternatives that draw or inject UI (overlay strip, flyout panel, appbar,
`Shell_TrayWnd` reparenting, explorer injection à la ExplorerPatcher/Windhawk) were
studied and **rejected** (ADR-0003, ADR-0005, ADR-0006).

Two honest costs: a one-time manual *Pin to taskbar* per launcher (assumed manual
pending spike S-8's evaluation of `TaskbarManager.RequestPinAppListEntryAsync`), and
the AUMID grouping behavior must be confirmed on every supported build family (C-2) — **spike S-3 is
the go/no-go on which this verdict and ADR-0006 are conditional**.

## Hard constraints

- Native only: Win32 / COM / Windows Runtime APIs. **No .NET runtime dependency.**
- WinUI 3 (via C++/WinRT) is allowed **only if** plain Windows APIs prove insufficient.
- Windows 11 only — **any edition with the standard desktop taskbar**, on the releases
  in Microsoft support (for any edition) at each release date; editions are not a
  discriminant (C-2), per-API build floors are documented in architecture §8.1, and
  the concrete release list lives in the test plan's qualification matrix.
- Modern C++ (C++20+), OOP design with inheritance where it fits naturally, KISS — no
  overdesign (ADR-0007).
- Full unit testing with coverage; qualification tests traceable to requirement IDs
  (ADR-0008).
- Documentation and architecture live in this repo, as code (Markdown + Mermaid + ADRs).
