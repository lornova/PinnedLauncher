# TODO

Two horizons: what must be fixed/implemented **before 1.0** (blocking the stable
release) and what is deliberately deferred **after 1.0**. Release stages and gates:
[docs/release-plan.md](docs/release-plan.md). Phasing:
[docs/implementation-plan.md](docs/implementation-plan.md).

## Before 1.0

### Decisions (deadline noted per item)
- [x] **Project name** — decided 2026-08-14: **PinnedLauncher** (GitHub availability
      checked — no collision).
- [x] **OSS license** — decided 2026-08-14: **GPL-3.0**; `LICENSE` added in the
      initial commit.
- [ ] **Code signing** — *decide before beta (0.8)*: unsigned (SmartScreen friction,
      R-6) vs certificate (cost); document the choice.

### Spikes (blocking architecture finalization — phase P0)
- [ ] **S-3** AUMID non-merge + identity propagation across app types, on every
      supported build family (C-2) — the
      go/no-go for the whole design (ADR-0006 gains a "verified" note or the project
      pivots).
- [ ] **S-4** Pin/unpin lifecycle: guided pin flow UX; pin-detection reliability
      (`User Pinned\TaskBar` heuristic); can Start be deep-linked to the entry?
      `IStartMenuPinnedList::RemoveFromList` for programmatic unpin on Win11.
- [ ] **S-5** Whether icon/name edits to the *source* shortcut propagate to an
      existing pin without a re-pin (icon cache + `SHChangeNotify`) — best-effort
      enhancement only; includes badge recomposition.
- [ ] **S-6** Elevation semantics: medium-IL proxy applies `runas` to the resolved
      target (UAC names the target; no double UAC, no lingering button); verify the
      confused-deputy guard — an elevated-started proxy must detect it and refuse
      config-driven launch (UC-6).
- [ ] **S-7** Jump-list tasks render for a proxy AUMID with no process running (quick
      sanity check).
- [ ] **S-8** Evaluate `TaskbarManager.RequestPinAppListEntryAsync` / secondary-tile
      pin APIs (unpackaged-app support, our generated Start entries) — could replace
      the manual pin gesture entirely. LAF gating is servicing-dependent (token
      required below KB5074105) and runtime-detectable via Microsoft's documented
      registry probe (architecture §8.1).
- [ ] **S-9** Validate the UIA test oracle (persistent pin vs same-named running
      button distinguishability) and define test-environment hygiene (dedicated
      profile/VM, reserved test-AUMID namespace, teardown, failed-run recovery).
- [ ] Management-window opens: `shell:AppsFolder` enumeration perf/ordering for the
      installed-apps picker.

### Engineering (phases P1–P3, mapped to releases in the implementation plan)
- [ ] Detailed design docs: config JSON schema, AUMID scheme, CLI spec
      (`PinnedLauncher.exe` / proxy args), error-handling & logging policy, threading
      model.
- [ ] Test plan (`docs/test-plan.md`) + Windows build matrix; traceability generator
      (`docs/traceability.md` from tagged tests).
- [ ] One-command **verification script** (`verify`: clean build + UT + coverage
      threshold + automated QT tier) — the project's quality gate; no CI
      infrastructure (release-plan §4).
- [ ] Core library: config store, models (0.1).
- [ ] Icon service: extraction, badge compositing, multi-size `.ico` writer (0.2).
- [ ] Shortcut + AUMID manager; windowless proxy exe; launch service (0.3).
- [ ] Management window: main list, add/edit, pin guide, presenters + UIA QTs (0.4).
- [ ] Jump-list publisher: per-launcher menus, wired to the shipped window CLI (0.5).
- [ ] Settings, config import/export (with preview), en/it/hu localization, accessibility
      pass, clean uninstall (UC-13) (0.6).
- [ ] Should-requirements completion: packaged-app/document/folder/URL targets (F-7),
      full per-launcher properties (F-8), elevation hardening, config-migration
      machinery + UTs (0.7 — feature-complete).
- [ ] User documentation: quick start with screenshots (before 0.8).
- [ ] Interactive QT protocol executed on full build matrix (0.8/0.9 gates).

## After 1.0

- [ ] **Launch groups** (UC-15 / F-14): one pin starting a set of targets.
- [ ] **Per-launcher global hotkeys** (F-13 remainder).
- [ ] Optional **tray icon** for quick settings access (management-window §8, off by
      default).
- [ ] Fuller **dark client area** for the management window via documented APIs only
      (ADR-0010 trade-off), or adoption of documented Win32 dark theming if Microsoft
      ever ships it.
- [ ] **Portable mode** (NF-13): config next to the exe.
- [ ] **winget** manifest / Microsoft Store consideration.
- [ ] **Migration assistant**: import targets from the old Quick Launch folder and/or
      existing taskbar pins.
- [ ] Additional languages beyond en/it/hu.
- [ ] Manual "check for updates" — permitted by NF-9 as the sole, explicitly
      user-invoked network operation; no telemetry.
- [ ] Optional: GitHub Actions workflow that just runs the verification script
      (hosted runners are free for public repos — no infrastructure of ours; value:
      clean-machine validation + badge).
- [ ] Icon freshness watcher: detect target icon changes proactively rather than on
      launch/edit (extends S-5 outcome).
