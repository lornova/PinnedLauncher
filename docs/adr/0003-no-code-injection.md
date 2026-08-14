# ADR-0003 — No code injection into explorer.exe or system processes

- Status: accepted
- Date: 2026-08-13

## Context

The only way to place UI literally *inside* the Windows 11 taskbar is to inject into
`explorer.exe` and hook the XAML taskbar (ExplorerPatcher, StartAllBack, Windhawk), or
to reparent a window into `Shell_TrayWnd` (TrafficMonitor). The feasibility study
(§4.1) documents the consequences observed across those projects: breakage on feature
updates *and* monthly cumulative updates, dependence on Microsoft PDB symbols for
private internals, Defender/AV false positives, and Windows 11 24H2 upgrade safeguard
holds placed on machines running such tools.

## Decision

The launcher never injects code into, hooks, patches, or reparents windows into
`explorer.exe` or any other process (constraints C-3, C-4). Integration with the taskbar
is achieved only via supported APIs — in the chosen design, native pins driven by
AppUserModelID shortcuts ([ADR-0006](0006-native-taskbar-pins.md)).

## Consequences

- The chosen design gets **full, real** taskbar integration for free: it uses the OS's
  own pinning rather than faking it, so the no-injection rule costs nothing here.
- We forgo the one thing only injection can do — adding arbitrary custom UI *inside* the
  taskbar — which is out of scope by decision (ADR-0006) anyway.
- No AV quarantine, no `C:\Windows` writes, no upgrade safeguard holds, no per-update
  breakage treadmill — the failure modes that plague ExplorerPatcher/Windhawk/StartAllBack
  simply do not apply.
- If literal in-taskbar custom UI is ever reconsidered, the route is contributing a
  Windhawk mod (inheriting their engine and maintenance community), not a bespoke
  injector in this codebase.
