# Requirements

IDs are stable and referenced from [architecture.md](architecture.md) and the ADRs.
Priorities use MoSCoW: **M**ust, **S**hould, **C**ould, **W**on't (this iteration).
Categories: `F-n` functional, `NF-n` non-functional, `Q-n` quality & process,
`C-n` constraints.

## Functional

| ID | Priority | Requirement |
|---|---|---|
| F-1 | M | Each launcher is a **native taskbar pin** in the pinned-app zone (after Start/Search, left of the running-app buttons); position is user-controlled via native drag, not forced by the app. |
| F-2 | M | A launcher pin **never merges with or expands into** the launched app's button: the target opens as its own separate taskbar button (distinct AUMID); the pin is unchanged (UC-2 invariant). |
| F-3 | M | Single left-click launches the target. |
| F-4 | M | Each launcher displays the target's shell icon by default (UC-1), with a small **launcher badge** composited into a corner (shortcut-arrow-style) so launcher pins are visually distinguishable from normally pinned apps; badge configurable (on/off, corner); icon override possible (UC-5). |
| F-5 | M | Add / remove / reorder launchers at runtime, persisted (UC-1, UC-3, UC-4, UC-8). |
| F-6 | M | Targets: Win32 executables, including `.lnk` shortcuts **resolving to Win32 executables** (a `.lnk` is classified by its resolved destination — management-window §5.2); `.lnk` to other destination kinds follow that kind (F-7). |
| F-7 | S | Targets: packaged/Store apps via AUMID activation; folders, documents, URLs (UC-16). |
| F-8 | S | Per-launcher properties: args, working dir, run-as-admin, window state (UC-5). |
| F-9 | S | Launcher-specific right-click menu via the pin's **Jump List tasks** (UC-7): change name/icon, add a new launcher, remove this launcher always; open target's folder and run-as-administrator **only for target kinds where they apply** (capability matrix, management-window §5.2). Modified-click semantics are **normatively defined by UC-6**: supported elevation is per-launcher through the proxy running at session-default integrity (`runas` on the resolved target); the native Ctrl+Shift-elevates-the-pin path is **refused across an elevation boundary** (confused-deputy guard, ADR-0011 — in no-boundary sessions the guard never fires and the click is an ordinary launch). |
| F-10 | S | Global settings UI (UC-10). |
| F-11 | W | Per-user autostart of the **optional background helper only** — the pins work with no process of ours running (UC-9). Deferred with the tray helper to **post-1.0** (TODO.md). |
| F-12 | C | Multi-monitor replication (UC-12). |
| F-13 | C | Keyboard navigation + UI Automation exposure (UC-14). |
| F-14 | C | Launch groups (UC-15). |
| F-15 | W | Unity-style **notification counters and progress bars** on launcher icons, and forwarding of the *target application's own* jump-list content onto launcher pins. (Distinct from F-4's launcher badge and F-9's management task menu, which **are** in scope.) |

## Non-functional

| ID | Priority | Requirement |
|---|---|---|
| NF-1 | M | **No .NET / no bundled runtime.** At most two native executables — the management app and the windowless proxy (uniform flavor B: architecture §3, ADR-0012) — plus an optional resource DLL. Statically linked CRT or OS-provided DLLs only. |
| NF-2 | M | No persistent process is required for the pins to work. Any optional background helper: < 20 MB private working set, ~0% CPU when idle, no polling. The windowless proxy launches the target and exits immediately. |
| NF-3 | M | Click → target launch initiated < 100 ms, measured proxy start → `ShellExecuteEx`/activation call; management window opens < 500 ms, measured process start → window visible. Protocol: median of 10 warm runs on the reference development machine; exact procedure in the test plan. Pins are OS-persisted, so nothing renders at logon. |
| NF-4 | M | Per-user install; no administrator rights required to install, run, or configure. |
| NF-5 | M | Per-Monitor v2 DPI awareness; correct rendering at mixed DPIs (UC-11). |
| NF-6 | M | Visual integration is **native by construction**: launchers are real taskbar pins, so theme, rounded corners, spacing, DPI and animations are the OS's, not ours. |
| NF-7 | M | Resilience: because pins are OS-owned, explorer restart, monitor/DPI churn and taskbar re-layout (UC-11) are handled by Windows; our config and proxy shortcuts must survive them intact. |
| NF-8 | M | **Behavioral robustness:** the app has no resident process, so detection is bounded to when its code runs — the management window performs a consistency check at each start (artifacts present and coherent with config; known-regression probes), and a grouping regression is inherently user-visible (pin expands in place = stock Windows behavior, nothing worse). Mitigation = diagnosis in the management window, guided repair (regenerate / re-pin), and a fix release. Never automatic taskbar modification beyond documented APIs; anything requiring a user gesture is tracked as *pending* and re-offered rather than silently dropped (carriers: the persisted `awaiting-pin`/`awaiting-repin` lifecycle states, architecture §4.3; states + reconciliation land 0.3, the re-offer UI 0.4). |
| NF-9 | M | No telemetry, ever. No network access in normal operation; the sole permitted network use is an explicit, user-invoked update check (post-1.0 item in TODO.md) that transmits nothing beyond the request itself. Config stays local (`%LOCALAPPDATA%`). |
| NF-10 | S | Accessibility: UIA tree, keyboard operability, high-contrast theme support. |
| NF-11 | S | Localizable strings — at least **en, it, hu** initially. |
| NF-12 | S | Config format is human-readable and diff-friendly (JSON), documented in-repo. |
| NF-13 | C | Portable mode (config next to the exe). |

## Quality & process

| ID | Priority | Requirement |
|---|---|---|
| Q-1 | M | **Modern C++**: C++20 minimum (newer standard features adopted as MSVC supports them). Contemporary idiom throughout: RAII everywhere, smart pointers / RAII wrappers for every OS handle and COM object, `std` types over hand-rolled ones, no raw owning pointers, warnings-as-errors. |
| Q-2 | M | **Object-oriented design, without dogma**: the design is OOP-first, and **inheritance is used wherever it is the natural fit** (is-a relationships, polymorphic seams, template-method skeletons) — it is not avoided for reasons of fashion. Composition remains the choice where it is the simpler fit. See ADR-0007. |
| Q-3 | M | **KISS — no overdesign**: no speculative abstractions, no pattern zoo, no DI frameworks, no layers that exist "for the future". Every abstraction must earn its place by a present need (testability seams qualify as a present need, see Q-6). See ADR-0007. |
| Q-4 | M | **Full unit testing with coverage**: every module has unit tests; line/branch coverage is measured on every build. The enforced gate is **line coverage = 100% of core (non-UI, non-OS-glue) modules minus named exclusions**; every exclusion (pure Win32/COM pass-through) is named and justified in the one declared exclusion file; branch coverage is reported for review, not gated. See ADR-0008. |
| Q-5 | M | **Qualification tests (QTs) validate the requirements**: every Must/Should requirement (F/NF) maps to at least one QT identified by the requirement's ID (Catch2 tag), recorded in a traceability matrix (`docs/traceability.md`, generated by joining test declarations with version- and attempt-matched execution results — ADR-0009). Three tiers: fully automated; **semi-automated** (a native dialog instructs the operator through the required user gesture — e.g. the one-time pin — then the outcome is verified programmatically via UI Automation / file system / process checks); manual visual checklist only for judgments that resist automation (e.g. badge legibility at 16 px). See ADR-0008, ADR-0009. |
| Q-6 | M | **Testable architecture**: all OS boundaries (shell COM interfaces, file system, registry, process launch) sit behind thin abstract interfaces so that core logic is unit-testable without a live shell — also the project's primary legitimate use of inheritance (Q-2). |

## Constraints

| ID | Constraint |
|---|---|
| C-1 | Native code only: modern C++ (Q-1), Win32 + COM + WinRT via C++/WinRT where needed. WinUI 3 admissible **only** if plain Win32/DirectX rendering proves insufficient (per project brief). No Electron, no .NET, no third-party GUI frameworks. |
| C-2 | Target OS: **Windows 11, any edition that ships the standard desktop taskbar** — Home (incl. Single Language), Pro, Pro Education, Pro for Workstations, Education, Enterprise (incl. multi-session and IoT), and the LTSC variants. **Editions are not a discriminant**: the taskbar shell and every API this design uses are edition-independent; the discriminant is the **build** (per-API availability floors: architecture §8.1 — all pre-date Windows 11; the one servicing-gated behavior is probed at runtime). Supported releases = those in Microsoft support *for any edition* at each release date (which includes Enterprise/Education tails and LTSC baselines); the authoritative list is the test plan's qualification matrix, which covers each supported **build family** on a representative edition — exhaustive edition coverage is unnecessary, it is the same shell. **Preconditions:** an interactive desktop session where unpackaged Win32 applications may run and user taskbar pinning is not disabled by policy; constrained configurations (e.g. **Windows 11 SE**, or environments whose policy blocks Win32 execution or taskbar pinning) are excluded. Windows 10 is out of scope. |
| C-3 | Must not modify, patch, or inject code into `explorer.exe` or other system processes (see ADR-0003 and the feasibility study's assessment of injection-based approaches). |
| C-4 | Must not require disabling Windows security features (code integrity, SmartScreen, Defender exclusions). |
| C-5 | Documentation as code: Markdown + Mermaid + ADRs in this repo (ADR-0002). |

## Explicit non-goals

- **Drawing any UI on or near the taskbar** — no overlay strip, no flyout panel, no
  appbar, no notification-area launcher grid. Launchers are native pins only. (User
  decision; see ADR-0006.)
- Replacing or re-implementing the whole taskbar (StartAllBack/ExplorerPatcher territory).
- Injecting into or reparenting windows into `explorer.exe` (ADR-0003).
- Windows 10 compatibility.
- Dock-style floating launchers detached from the taskbar (RocketDock territory).
- Search/command-palette launching (PowerToys Run / Flow Launcher already do this well).
