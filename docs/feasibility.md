# Feasibility study

- Date: 2026-08-13
- Status: complete — verdict in [§7](#7-verdict-and-recommended-next-steps)
- Inputs: Microsoft Learn documentation (checked via the official docs index on the
  study date), project repositories and community reports for prior art (see inline
  links), [ui-reference.md](ui-reference.md) for the UX model.

## 1. Problem statement

Windows 11 removed the Quick Launch mechanism (taskbar toolbars). Its pinned-apps model
conflates *launchers* with *running windows*: a pinned icon expands in place into the
running application's button. The goal is a native app that restores true quick-launch:
launcher buttons in the **pinned-app zone** (after Start/Search, left of the running
apps), each wearing the target's icon and name and launching it, strictly separate from
running-application buttons — i.e. **never expanding in place**
([requirements](requirements.md) F-1, F-2), with no .NET dependency (NF-1, C-1).

## 2. Background: what Windows 11 actually removed

| Windows ≤ 10 mechanism | Windows 11 status |
|---|---|
| Quick Launch toolbar (a taskbar toolbar over `%AppData%\Microsoft\Internet Explorer\Quick Launch`) | Folder still exists; the "Toolbars → New toolbar" taskbar UI that mounted it is **removed**. |
| Taskbar toolbars in general (Links, Address, Desktop, custom) | **Removed** — confirmed repeatedly by Microsoft Q&A moderators; a deliberate design decision, not a hidden setting. |
| Deskbands (`IDeskBand` shell extensions hosted in the taskbar) | API deprecated since Windows 8; the Win11 XAML taskbar **does not host deskbands at all** (killed BatteryBar, NetSpeedMonitor, …). |
| Movable taskbar, ungrouped buttons with labels (as toolbar substitutes) | Removed / re-added only partially over time. |

The Windows 11 taskbar is a new XAML implementation (`Taskbar.View.dll` hosted by
`explorer.exe`) that Microsoft iterates on aggressively — in 24H2 the dormant legacy
taskbar code was deleted from `explorer.exe` entirely, breaking every tool that revived
it.

## 3. Platform constraints (from official documentation)

These are the facts that bound every possible design:

1. **No extension point inside the taskbar.** There is no supported API to insert
   third-party UI into the Windows 11 taskbar. Deskbands and toolbars are gone (§2).

2. **No API pins arbitrary apps.**
   [`TaskbarManager.RequestPinCurrentAppAsync`](https://learn.microsoft.com/windows/apps/develop/windows-integration/pin-to-taskbar)
   can only request pinning of **the calling app itself**, shows a user-consent dialog,
   requires the app to be foreground and to have a Start menu entry — and was gated
   behind a Limited Access Feature token (`com.microsoft.windows.taskbar.pin`) until
   the restriction's removal began with KB5074105 (January 2026, builds 26x00.7705).
   The enterprise route
   ([taskbar layout XML / policy](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps))
   is provisioning-time, periodically re-applied, and not usable as an interactive
   consumer mechanism.
   **Resolved (spike S-8, 2026-08-15,
   [spikes/s8-pinapi.md](spikes/s8-pinapi.md)):** from an unpackaged desktop app,
   `RequestPinCurrentAppAsync` pins a generated Start entry when the process assumes
   that entry's explicit AUMID — one consent dialog carrying the launcher's name and
   icon, and the landed pin is equivalent to a gesture pin. The *beyond-current-app*
   APIs are closed to unpackaged callers:
   [`RequestPinAppListEntryAsync`](https://learn.microsoft.com/uwp/api/windows.ui.shell.taskbarmanager)
   and the secondary-tile trio fail with `0x8000000E` *caller must have package
   identity*. The design pins **API-first with the guided gesture as fallback**, the
   posture user-configurable.

3. **Pin placement is fixed to the pinned zone.** Pins live in the single
   centered/left group; their order is user- or policy-controlled; nothing places a
   pin adjacent to the notification area. (Historical note: the study initially
   targeted right-side placement, which pins cannot provide; the requirement was later
   corrected to the pinned zone — today's F-1 — which pins satisfy natively.)

4. **Notification-area icons are supported but user-gated.** `Shell_NotifyIcon` is
   stable, documented, and puts icons on the far right — but
   [icons land in the overflow by default and visibility "cannot be programmatically
   controlled; only the user is allowed to choose which notification icons appear"](https://learn.microsoft.com/windows/win32/shell/taskbar-extensions).
   Tray icons are also small (16 px class) and UX guidelines reserve the area for
   status, not launchers.

5. **The AppBar API is alive and not deprecated.**
   [`SHAppBarMessage`](https://learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shappbarmessage)
   still registers application desktop toolbars that reserve screen-edge space; the
   system adjusts their rectangle so **the taskbar always stays on the outermost
   edge** — i.e. an appbar docked at the bottom becomes a *second bar above the
   taskbar*, never part of the taskbar row. It also delivers the useful
   `ABN_FULLSCREENAPP` notification (the supported "a fullscreen app is active" signal).

6. **Taskbar identity is AUMID-keyed.** Grouping and pin identity follow the
   [AppUserModelID](https://learn.microsoft.com/windows/win32/shell/appids) of the
   shortcut/window/process, not the executable path. Two different AUMIDs → two
   separate taskbar entities. This is the documented basis for the "pinned proxy
   shortcut that never expands in place" technique — the chosen design
   ([architecture.md](architecture.md)).

## 4. Prior art survey

Full agent research notes are condensed here; links are to the primary sources.

### 4.1 Injection into `explorer.exe` (rejected territory, but instructive)

| Project | Technique | State (Aug 2026) |
|---|---|---|
| [ExplorerPatcher](https://github.com/valinet/ExplorerPatcher) (GPL-2.0, C/C++) | DLL search-order hijack (`dxgi.dll` into `C:\Windows`) → hooks inside explorer, resolves internals via Microsoft PDBs; on 24H2 ships a full taskbar **reimplementation** | Works, but: broke on every feature update, Defender flagged it as a trojan (false positive), 24H2 placed an upgrade safeguard hold on machines running it |
| [StartAllBack](https://www.startallback.com/) (closed, paid, native) | DLL injection + hooking; 24H2 forced a full taskbar reimplementation | Works on 22H2–25H2; also hit by a 24H2 compatibility block until rebuilt |
| [Windhawk](https://github.com/ramensoftware/windhawk) + [taskbar mods](https://github.com/ramensoftware/windhawk-mods) (GPL-3.0, C++) | Generic injection/hook engine; taskbar mods rewrite the **XAML visual tree** live | Actively maintained; individual mods repeatedly broken by monthly cumulative updates (e.g. KB5053656, KB5031323) |
| [7+ Taskbar Tweaker](https://ramensoftware.com/7-taskbar-tweaker) | Hooks the classic taskbar only | Explicitly **will not** support the Win11 taskbar; author moved effort to Windhawk mods |

**Lesson:** injection achieves perfect visual integration and is the only way to be
literally *inside* the taskbar — at the cost of a permanent maintenance treadmill,
antivirus false positives, and Microsoft actively blocking upgrades on machines running
such tools. This violates our constraints C-3/C-4 and the resilience requirement NF-7.
(If perfect integration ever becomes non-negotiable, the sane route is contributing a
**Windhawk mod** rather than shipping our own injector — recorded in ADR-0003.)

### 4.2 Overlay windows over/near the taskbar (the surviving pattern)

| Project | Technique | State |
|---|---|---|
| [ElevenClock](https://github.com/marticliment/ElevenClock) (Python/Qt) | Borderless topmost overlay positioned over the taskbar clock area; **continuously re-raises itself**; explicit fullscreen and RDP detection | Worked across Win11 builds for years; archived 2025 (author moved on), pattern proven |
| [TrafficMonitor](https://github.com/zhongyang219/TrafficMonitor) (C++/MFC, GPL) | **Reparents its window as a child of `Shell_TrayWnd`** (inside the taskbar!), with plain-window fallback; reads `TaskbarAl` registry for alignment; "avoid Widgets overlap" option | Works, actively maintained, but embedding fails sporadically (security software, Start menu open) and needs per-build workarounds |
| [RoundedTB](https://github.com/RoundedTB/RoundedTB) (C#, GPL-3.0) | Window-region reshaping of the taskbar + dynamic sizing | Archived 2023; dynamic mode broke with taskbar layout changes; auto-hide flicker |
| [TranslucentTB](https://github.com/TranslucentTB/TranslucentTB) (C++, GPL-3.0) | `SetWindowCompositionAttribute` on `Shell_TrayWnd` from outside — no injection | **The most reliable project in this survey**; works Win10+Win11, low breakage — because its API surface is comparatively stable |
| Docks: [Winstep Nexus](https://winstep.net/) (active, 24H2 fixes), ObjectDock 3.0 (revived 2024), RocketDock (dead) | Free-floating overlay dock windows | Overlay docks survive on Win11 precisely because they don't touch the taskbar |

**Documented pain points of the overlay pattern** (all confirmed across these projects):
z-order contention with the topmost taskbar (constant re-raising; a rogue fullscreen
topmost window can even knock the *taskbar* out of topmost — see
[RudeWindowFixer](https://github.com/dechamps/RudeWindowFixer)); fullscreen-app
detection (supported signal: `ABN_FULLSCREENAPP`); auto-hide taskbar tracking/flicker;
per-monitor DPI churn; explorer restarts recreating `Shell_TrayWnd` (must reattach);
Win11 geometry shifts (centered vs left alignment via `TaskbarAl`, Widgets button, tray
width changes).

### 4.3 Quick-Launch revivals (the supported-but-compromised pattern)

- [TrayToolbar](https://github.com/brondavies/TrayToolbar) (open source, .NET): tray
  icon → vertical popup menu of shortcuts. Explicitly built as a replacement for the
  removed Win11 toolbars.
- **SystemTrayMenu** (open source, .NET, MS Store): point it at a folder of `.lnk`
  files (e.g. the old Quick Launch folder), open via tray icon or hotkey.
- [AppSwitcherBar](https://github.com/adamecr/AppSwitcherBar) (MIT, .NET 6 WPF):
  **proves the AppBar API on Windows 11** — docks a real bar adjacent to the taskbar
  via `SHAppBarMessage`, handles per-monitor DPI, enumerates windows by AUMID.

These never break, because they use only supported surfaces — but none of them puts
icons *visually into the taskbar row*.

### 4.4 UI model reference

GNOME's dash-to-panel and KDE's Icons-only Task Manager both offer, as an explicit
mode, exactly the separation semantics we require (launcher zone that never absorbs
running windows). Distilled option surfaces are in [ui-reference.md](ui-reference.md).

## 5. Technique assessment against our requirements

*(Historical table: the Placement column reflects the study-time right-side
assumption; F-1 was later corrected to the pinned zone, which is why the chosen row —
and only it — is assessed against the final requirement.)*

| Technique | Placement (F-1) | Separation (F-2) | Supported APIs only (C-3/C-4) | Update resilience (NF-7/8) | Notes |
|---|---|---|---|---|---|
| Explorer injection / XAML hook | ✅ perfect | ✅ | ❌ | ❌ | Rejected (ADR-0003) |
| Child window into `Shell_TrayWnd` | ✅ | ✅ | ❌ (undocumented) | ⚠️ breaks sporadically | TrafficMonitor survives, barely |
| **Overlay topmost strip over taskbar** | ✅ visually (not structurally) | ✅ | ⚠️ benign but unsupported placement | ⚠️ engineering-heavy, proven for years | ElevenClock pattern |
| AppBar docked strip | ❌ second bar above taskbar | ✅ | ✅ | ✅ | AppSwitcherBar pattern |
| One tray icon per launcher | ⚠️ right side, but 16 px + user must promote each | ✅ | ✅ | ✅ | UX-poor at scale |
| Tray button + flyout panel | ⚠️ one icon; panel on demand | ✅ | ✅ | ✅ | Two clicks per launch |
| **Pinned AUMID proxy shortcuts** | ✅ pinned zone = the wanted spot (after Start, before running apps) | ✅ (verify per C-2, spike S-3) | ✅ | ✅ | **Chosen design** — no strip at all; zero moving parts |

## 6. Risks (of the chosen design)

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-1 | AUMID grouping/identity computation changes on a future build so a pin merges with its target | Low–Medium | High (breaks the core invariant) | Flavor B (windowless proxy decoupling the target's launch from the pin's identity — no API can set another process's AUMID); spike S-3 up front; failure is per-launcher and no worse than stock pin behavior |
| R-2 | The one-time manual "Pin to taskbar" is friction / users get stuck | Medium | Low–Medium | Clear guided flow (S-4); pre-create the Start-menu entry so the pin action is one right-click |
| R-3 | Target updates its icon and the proxy goes stale | Medium | Low | Re-extract icon on launch / periodically (S-5) |
| R-4 | Elevated targets cause a double UAC or a lingering proxy button | Low | Low | Windowless proxy + correct `runas` handling (S-6) |
| R-5 | Microsoft ships a native Quick Launch equivalent | Low | Happy obsolescence | — |
| R-6 | Defender/SmartScreen friction for an unsigned proxy exe | Low (no injection, no system writes) | Low | Flavor A (no exe) where possible; optional code signing later |

## 7. Verdict and recommended next steps

**Feasible, cleanly.** The design is native Windows 11 taskbar pins used as launcher
proxies: each launcher is a shortcut carrying the target's icon and name plus a distinct
AppUserModelID, so clicking it launches the target while the running app appears as its
**own separate taskbar button** — the pin never expands in place. The pins sit in the
pinned-app zone (after Start/Search, left of the running apps), which is exactly the
requested location, and the user drags them to taste.

Two refinements complete the UX, both on supported surfaces: a small **launcher badge**
composited into the generated icon (pure image work — the shell shows no shortcut arrow
on pins, and `SetOverlayIcon` only applies to running windows), and a **per-launcher
right-click menu** via Jump List tasks (`ICustomDestinationList`, keyed to each proxy's
AUMID; tasks are documented to work while the app is not running).

This uses only documented shell APIs (`IShellLink`, `IPropertyStore`,
`IShellItemImageFactory`, `ICustomDestinationList`, `ShellExecuteEx`, AUMID
properties). It draws **nothing** on
the taskbar — no overlay, flyout, appbar, reparenting, or injection (all rejected, per
the requirements' non-goals, ADR-0003 and ADR-0005). There is **no** fragile shell-geometry/z-order code
and **no** custom over-taskbar renderer, so the two biggest maintenance liabilities of
the alternatives simply don't exist here. Plain Win32 + COM; **no WinUI, no .NET**
(NF-1, C-1). Full detail in [architecture.md](architecture.md); decision in
[ADR-0006](adr/0006-native-taskbar-pins.md).

The two honest costs: a **one-time pin consent** per launcher (a consent dialog via
the S-8-validated `RequestPinCurrentAppAsync` route, guided gesture as fallback), and
dependence on **AUMID grouping behavior** staying as documented across builds — which
is why this verdict, and ADR-0006, are **conditional on spike S-3**.

Recommended next steps (in order):
1. **Spike S-3 (central go/no-go):** on every C-2-supported build, confirm a proxy
   `.lnk` with a distinct AUMID launches the target as its **own** button while the pin
   stays put — across a packaged app, a plain Win32 exe, and an exe that sets its own
   AUMID; nail down the identity-propagation handling (flavor A vs B).
2. **Spike S-4:** the pin/unpin lifecycle — guided pin flow, pinned-copy detection,
   and `IStartMenuPinnedList::RemoveFromList` for programmatic unpin.
3. **Spikes S-5 – S-9:** pin-edit propagation, elevation, jump-list rendering,
   `TaskbarManager` pin-request evaluation, UIA test-oracle validation
   (full definitions: [architecture §9](architecture.md) and the implementation plan).
4. Then start the MVP on the [architecture.md](architecture.md) core.
