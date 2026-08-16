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
- [x] **Implementation flavor (P0.3)** — decided 2026-08-16: **uniform flavor B**
      ([ADR-0012](docs/adr/0012-uniform-flavor-b.md)) — every pin targets the
      windowless proxy; flavor A retired (S-3 merge evidence, per-launch feature
      dependencies, no platform-risk hedge value).
- [ ] **Code signing** — *decide before beta (0.8)*: unsigned (SmartScreen friction,
      R-6) vs certificate (cost); document the choice. Weight increased by
      ADR-0012: no flavor-A "no exe" avoidance remains.

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
      `Full` — adopted, with boundary semantics and the supported
      UAC-off / built-in-Administrator environments, in ADR-0011
      (2026-08-16; no-boundary qualification at 0.7.x). Side finding: fresh Start entries reach `shell:AppsFolder` only
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
- [x] **S-8** `TaskbarManager` pin APIs — **completed 2026-08-15**
      ([docs/spikes/s8-pinapi.md](docs/spikes/s8-pinapi.md)):
      `RequestPinCurrentAppAsync` works from our unpackaged exe against a
      generated Start entry when the helper assumes the launcher's AUMID —
      the consent dialog carries the launcher's name/icon, the landed pin
      is equivalent to a gesture pin on the S-4 and S-9 oracles, and S-4's
      `RemoveFromList` unpins it. `RequestPinAppListEntryAsync` and the
      secondary-tile APIs: `0x8000000E` *caller must have package
      identity* (closed to us). LAF runtime detection verified post-KB
      (registry probe + `TryUnlockFeature` agree: no token). Caveats:
      gate every request on `IsCurrentAppPinnedAsync` (the dialog
      re-appears on already-pinned requests, contra docs); the helper
      needs foreground-activation rights (background launch just blinks);
      `IsPinningAllowed` is foreground-sensitive. Decision: pin guide goes
      **API-first with gesture fallback**, posture exposed as a pin-flow
      setting (API-first / API-only / manual).
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
- [x] Management-window opens: `shell:AppsFolder` enumeration perf/ordering for the
      installed-apps picker — **completed 2026-08-15**
      ([docs/spikes/appsfolder-enum.md](docs/spikes/appsfolder-enum.md)): 166
      items with names + AUMIDs in ≤ 0.5 s warm via the slow automation layer
      (upper bound); returned order NOT sorted (picker sorts itself); parse
      name = `System.AppUserModel.ID` on every sampled item but is a raw file
      path for some Win32 entries (opaque `ParseName`-able identity); packaged
      entries classified by `!`. `shell:AppsFolder` confirmed as the picker's
      single source; no caching layer warranted.

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
- [ ] Shortcut + AUMID manager; windowless proxy exe; launch service; persisted
      lifecycle states + state-aware reconciliation (NF-8 core, architecture §4.3)
      (0.3).
- [ ] Management window: main list, add/edit, pin guide, pending-state re-offer UI
      (NF-8), presenters + UIA QTs (0.4).
- [ ] Jump-list publisher: per-launcher menus, wired to the shipped window CLI (0.5).
- [ ] Settings, config import/export (with preview), en/it/hu localization, accessibility
      pass, clean uninstall (UC-13) (0.6).
- [ ] Should-requirements completion: packaged-app/document/folder/URL targets (F-7),
      full per-launcher properties (F-8), elevation hardening — incl. the ADR-0011
      guard QTs on the UAC-off / built-in-Administrator environment profile —
      config-migration machinery + UTs (0.7 — feature-complete).
- [ ] User documentation: quick start with screenshots (before 0.8).
- [ ] Interactive QT protocol executed on full build matrix (0.8/0.9 gates).

## After 1.0

- [ ] **Launch groups** (UC-15 / F-14): one pin starting a set of targets.
- [ ] **Per-launcher global hotkeys** (the UC-14 stretch feature; F-13 covers
      keyboard navigation/UIA, not hotkeys — assign a new stable requirement ID
      if this is promoted).
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
- [ ] **Focus-or-launch** *(very low priority)*: optional per-launcher click
      behavior — focus the target's existing window instead of launching (UC-6 /
      UC-10 Could; capability matrix drafted in management-window §5.2). At
      promotion: reserve **F-16**, design the window-matching heuristics
      (multi-window targets, launcher-stub targets, packaged ⚠), and fix the
      elevation precedence — focus an existing window **before** any
      launch/elevation, so no UAC fires when nothing launches.
