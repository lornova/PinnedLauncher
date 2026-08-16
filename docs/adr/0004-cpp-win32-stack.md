# ADR-0004 — C++20 / Win32 / COM stack, no WinUI, no .NET

- Status: accepted
- Amended: 2026-08-16 — [ADR-0012](0012-uniform-flavor-b.md) decided uniform
  flavor B: the windowless proxy exe is a **definite** second executable, no
  longer "optional … for flavor B".
- Date: 2026-08-13

## Context

Project brief: native only, no .NET; WinUI 3 admissible only if plain Windows APIs are
insufficient (C-1, NF-1). Under the chosen design ([ADR-0006](0006-native-taskbar-pins.md))
the launchers are **native taskbar pins drawn by the OS**; the app itself renders no UI
on the taskbar. The only GUI is an ordinary management/settings window, plus (optionally)
a tiny windowless proxy exe.

## Decision

- Language: C++20, MSVC, CMake; statically linked CRT; single per-user exe
  (+ optional windowless proxy exe for flavor B).
- APIs: Win32 + COM — `IShellLink` (proxy shortcuts), `IPropertyStore` (explicit
  AUMID; shortcut icon/name are authoritative, no `Relaunch*` properties),
  `IShellItemImageFactory` (icon extraction), `ShellExecuteEx`,
  `IApplicationActivationManager` (plain COM; created `CLSCTX_LOCAL_SERVER` from
  short-lived processes per its documentation); C++/WinRT only where an API is
  genuinely WinRT-shaped (theme queries, `TaskbarManager` evaluation). No XAML, no
  Windows App SDK.
- Management/settings UI: an ordinary Win32 window/dialog. **No custom GPU rendering, no
  layered over-taskbar window** — the OS draws the pins.

## Consequences

- Zero runtime dependencies; footprint/startup targets (NF-2/NF-3) are trivial.
- WinUI 3 was evaluated and is **not needed** — nothing in the design requires it.
- No over-taskbar renderer, hit-testing, or z-order handling exists anywhere in the
  stack — the OS draws the pins ([ADR-0006](0006-native-taskbar-pins.md)). Accessibility and
  keyboard access to the launchers are inherited from the native taskbar (e.g. Win+digit
  launches a pinned app); only the settings window needs standard a11y work.
