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
- [x] **S-3** AUMID non-merge + identity propagation — **GO recorded 2026-08-15**
      ([docs/spikes/s3-aumid.md](docs/spikes/s3-aumid.md)): verified on family
      26200, all flavor-B cases pass; flavor-A pins to plain Win32 exes merge via
      target-path association → flavor B mandatory there. ADR-0006 annotated.
      Families 26100/28000 stay as non-blocking confirmation runs (first entries
      of the P2 qualification matrix); 22631 descoped (out of support
      2026-11-10).
- [x] **S-4** Pin/unpin lifecycle — **completed 2026-08-15**
      ([docs/spikes/s4-pinflow.md](docs/spikes/s4-pinflow.md)): pin guide
      deep-links via `SHOpenFolderAndSelectItems` on `shell:AppsFolder\<AUMID>`
      (entry pre-selected; drag-to-taskbar and Start routes as fallbacks); the
      `User Pinned\TaskBar` copy is a synchronous, route-independent signal
      (Taskband blob is lazy — never use for live detection);
      `RemoveFromList` validated → UC-3 unpins programmatically (S_FALSE on
      success; gesture fallback kept).
- [x] **S-5** Icon/name edit propagation — **completed 2026-08-15**
      ([docs/spikes/s5-editprop.md](docs/spikes/s5-editprop.md)): no documented
      nudge (every `SHChangeNotify` form, `ie4uinit -show`) propagates in-place
      icon rewrites or source renames to an existing pin — only an Explorer
      restart does → best-effort enhancement **rejected**; the §4.2
      regenerate-and-re-pin guide stands alone. Icon artifacts keep a stable
      path (the pinned copy references it forever; heals next session);
      `IShellLink` icon edits preserve the AUMID.
- [x] **S-6** Elevation semantics — **completed 2026-08-15**
      ([docs/spikes/s6-elevation.md](docs/spikes/s6-elevation.md)): medium-IL
      proxy + `runas` on the resolved target verified — one UAC naming the
      target, target elevated as its own button, silent `ERROR_CANCELLED` on
      decline, no lingering button (R-4 cleared). All three elevated-start
      vectors (Ctrl+Shift+click; jump-list *run as administrator*, which the
      shell does offer; programmatic `RunAs`) detected and refused before the
      config is read. Guard predicate for P1: refuse iff elevation type
      `Full`. Side finding: fresh Start entries reach `shell:AppsFolder` only
      after an indexing lag — the pin guide must poll `ParseName` before
      deep-linking (management-window §5.3).
- [x] **S-7** Jump-list tasks — **completed 2026-08-15**
      ([docs/spikes/s7-jumplist.md](docs/spikes/s7-jumplist.md)): tasks
      committed for the proxy AUMID before any pin existed render on the
      pin's jump list with no process running (separator + placement above
      the system entries included); clicked tasks invoke the target with
      their stored arguments; re-commit updates the menu with no staleness;
      `DeleteList` removes it. Full S_OK API trace on 26200. Second datum
      for the S-6 AppsFolder indexing lag: fresh entry parseable after 3 s
      of polling.
- [ ] **S-8** Evaluate `TaskbarManager.RequestPinAppListEntryAsync` / secondary-tile
      pin APIs (unpackaged-app support, our generated Start entries) — could replace
      the manual pin gesture entirely. LAF gating is servicing-dependent (token
      required below KB5074105) and runtime-detectable via Microsoft's documented
      registry probe (architecture §8.1).
- [x] **S-9** UIA test oracle + hygiene — **completed 2026-08-15**
      ([docs/spikes/s9-uiaoracle.md](docs/spikes/s9-uiaoracle.md)): taskbar
      buttons expose `AutomationId = "Appid: <AUMID>"` (pin) vs
      `"Window: 0x<hwnd>"` (running window) — the pin is identifiable by its
      AUMID even against a same-named running target, and the F-2 invariant
      is asserted by element comparison across states (held exactly in the
      run). Hygiene defined and demonstrated: reserved
      `PinnedLauncher.Test.*` namespace, programmatic leftover sweep,
      gesture-free teardown; dedicated profile/VM deferred to the P2
      matrix, which also varies `TaskbarGlomLevel`. ADR-0009 amended;
      oracle revalidates per build family alongside the S-3 confirmation
      runs.
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
      launch/edit. Bounded by the S-5 outcome: regeneration alone refreshes a pin
      only at the next Explorer session (no live nudge exists), so the watcher's
      value is early regeneration plus, at most, prompting a re-pin.
