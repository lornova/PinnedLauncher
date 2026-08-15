# Spike S-9 — UIA test oracle validation + test-environment hygiene

- Step: [implementation-plan](../implementation-plan.md) P0.2.
- Status: **complete — accepted outcome recorded 2026-08-15 (§7)**; executed
  via the guided runner, raw data in
  `spikes/s9-uiaoracle/results/s9-run-20260815-213556.json`.
- Feeds: [ADR-0009](../adr/0009-test-environment.md) (the UI-Automation
  oracle bullet — "validated by spike S-9 before any QT depends on it"),
  the P2 test plan's **test-environment hygiene** section
  ([implementation-plan](../implementation-plan.md) P2 row), F-2/NF-8 (the
  invariant and regression the oracle asserts), architecture §9's S-9 line.
- Throwaway artifacts: [`spikes/s9-uiaoracle/`](../../spikes/s9-uiaoracle/README.md).

## 1. Mechanism model and questions under test

The semi-automated QTs (ADR-0009) verify gestures with code, not eyeballs:
after the pin gesture, **UIA must assert** that the launcher button exists;
after a launch, that the target opened as a **separate** button while the
pin stayed unchanged (F-2, the core invariant; its violation — the pin
expanding in place — is exactly the NF-8 regression signature). The oracle's
worst case is a launcher whose display name **equals** the running target's
button name: if UIA can only see names, the oracle is blind. The strong
hypothesis to verify: the Win11 taskbar exposes each button's **AUMID as its
UIA `AutomationId`** — which would make the oracle trivial, language-
independent, and name-collision-proof, since every launcher pin carries our
explicit AUMID.

A read-only pre-run probe with `s9uia.exe` on this machine's existing pins
(2026-08-15, 26200.9168) already refined the hypothesis: a pinned
not-running button exposes `automationId="Appid: <AUMID>"` (e.g.
`Appid: Microsoft.Windows.RemoteDesktop`), a running-window button
`automationId="Window: 0x<hwnd>"` — the **prefix alone is structural**
(pin vs window), and the localized `Name` suffixes (*bloccato*, *N finestra
in esecuzione*) are informative but never load-bearing. The run validates
this on our own article and under the name collision.

- **Q1 — visibility and identity of the pin button.** Is the pinned
  launcher button findable in the UIA tree under the taskbar at all, and
  what does it expose: `AutomationId` (= our AUMID?), `Name`, `ClassName`,
  control type, `LegacyIAccessible` state, offscreen flag?
- **Q2 — distinguishability in the worst case, and the invariant
  assertion.** With a same-named target window running (name collision by
  construction): do **two** buttons appear; does exactly **one** carry our
  AUMID as `AutomationId`; what identifies the running one (derived ID,
  localized "running" name suffix, state bits); and — the F-2 assertion —
  is the pin's element **byte-identical in properties** to its
  pin-alone baseline while the target runs, and again after the target
  closes?
- **Q3 — test-environment hygiene.** Define and *demonstrate* the rules the
  QTs need:
  - **reserved test-AUMID namespace** — inaugurated by this spike:
    `PinnedLauncher.Test.*`, disjoint from the product's
    `PinnedLauncher.Proxy.*`, so test sweeps can key on the prefix without
    ever touching real launchers;
  - **failed-run recovery** — a preflight sweep that enumerates
    `User Pinned\TaskBar\*.lnk`, reads each AUMID (the pinned copy retains
    the property store), flags `PinnedLauncher.*` leftovers, and unpins
    them programmatically (S-4's `RemoveFromList`);
  - **gesture-free teardown** — the run's own cleanup, demonstrated fully
    programmatic;
  - **dedicated profile/VM** — a recommendation for the P2 matrix (spikes
    run on the dev profile; release-gate QTs should not).

## 2. Accepted outcome

The spike closes when Q1–Q3 have recorded answers and:

- the **oracle rule** is stated for ADR-0009's harness helper (expected
  form: *a taskbar button with `AutomationId == <launcher AUMID>` is the
  pin; any same-named button without it is the target; the pin's element
  must stay at its baseline while the target runs*) — or, if UIA cannot
  distinguish, the fallback is recorded: the oracle degrades to the
  file-system + process signals (S-4) and F-2's button-level assertion
  becomes a manual checklist item;
- the hygiene definitions (namespace, sweep, teardown, profile/VM
  recommendation) are on record for the P2 test plan;
- the **revalidation rule** is restated: family 26200 evidence now; the
  oracle protocol rides along the S-3 confirmation runs on 26100/28000 and
  re-runs whenever the C-2 matrix gains a build family (ADR-0009).

Scope bounds: primary taskbar only (`Shell_TrayWnd`; multi-monitor
secondary taskbars are a P2 concern), single-window target (multi-window
grouping details belong to the P2 test plan if any QT needs them). The
taskbar **combine mode** (`TaskbarGlomLevel`) changes running-button
naming/grouping and is recorded per run — this machine runs
combine-when-full with labels (level 1); the P2 matrix must exercise the
default combine mode too.
Tool limitation: non-ASCII characters in dump values may mojibake in
console capture (narrow output); every oracle-relevant value here is ASCII.

## 3. Environment

- Machine: physical, Windows 11 Pro 26200.9168 (25H2 — same image as the
  S-4..S-7 runs), it-IT · Date: 2026-08-15 · Artifacts: repo working tree.
- Taskbar mode: `TaskbarGlomLevel = 1` (combine when full, labels shown) —
  recorded because it shapes running-button naming; the P2 matrix must also
  exercise the default combine mode.
- Baseline: 5 pre-existing pins; preflight hygiene sweep found **no**
  `PinnedLauncher.*` leftovers (clean environment); gate G0 PASS.
- Pin flow: AUMID indexed in `shell:AppsFolder` after 3.1 s of polling
  (third latency datum for the S-6 finding: ~3 s twice, >28 s once); deep
  link all S_OK, entry pre-selected.
- Runner note: the two count-of-one UIA polls recorded `detected: false`
  due to a runner counting bug (a single element unrolled to a bare
  hashtable whose `.Count` is its key count); the timeout path still
  captured the elements, so every §6 value is real measured data. Fixed in
  the runner post-run for the confirmation re-runs; the empty
  change-lists serialized as `null` in the JSON mean *no changes*.

## 4. Test articles

| Piece | Role |
|---|---|
| `bin\s9uia.exe` | Console UIA walker (`IUIAutomation`, native COM — the same API the ADR-0009 harness helper will use): dumps every named/identified element under the taskbar as one `key="value"` line — control type, `Name`, `AutomationId`, `ClassName`, `LegacyIAccessible` state, offscreen, bounding rect — optionally filtered by a case-insensitive substring matched against `Name` or `AutomationId` |
| `bin\s9target.exe` | Real windowed app (title from its command line, default *S9 pin test*): its running taskbar button carries **exactly the pin's display name** — the collision under test. Closed gracefully by the runner (`CloseMainWindow`) |
| Proxy shortcut | `S9 pin test.lnk` → `charmap.exe` (never clicked; targeting the running exe itself would trip S-3's flavor-A path-association merge and destroy the two-button scenario), display name **identical** to the target window title, AUMID `PinnedLauncher.Test.S9Oracle1` — the first use of the reserved test namespace. Gate **G0**: independent AUMID read-back + binaries present |

Pin-route note (S-6/S-7 findings): the runner polls `ParseName(<AUMID>)` on
`shell:AppsFolder` before deep-linking, then pins via the S-4-decided
`SHOpenFolderAndSelectItems` deep link.

## 5. Protocol

**Execution: run `.\Invoke-S9Protocol.ps1`** — a guided runner in the
S-4..S-7 mold; almost everything here is automatable (UIA dumps, launches,
comparisons, teardown), so human steps shrink to the pin gesture and two
visual confirmations. Every measurement and answer lands in
`results\s9-run-<timestamp>.json` for transcription into §6.

### 5.1 Hygiene sweep, article, pin

1. **Preflight sweep** (the failed-run-recovery reference implementation):
   enumerate the pin folder, read each `.lnk`'s AUMID, flag
   `PinnedLauncher.*` leftovers and unpin them programmatically — via the
   Start-menu source when it still exists, else against the pinned copy
   itself (a path form S-4 never needed — its outcome is a bonus datum).
2. Generate the article (gate G0); poll `shell:AppsFolder`; pin via the
   deep link; confirm via the pin-folder signal.

### 5.2 Q1 — pin alone

3. Auto: `s9uia` filtered on the display name and on the AUMID. Expected:
   exactly one element; record all its properties; check
   `AutomationId == PinnedLauncher.Test.S9Oracle1`. Human: exactly one
   *S9 pin test* button visible.

### 5.3 Q2 — same-named running target, invariant, negative control

4. Auto: start `s9target.exe "S9 pin test"`; poll `s9uia` until the
   name-filtered element count reaches 2 (timeout, then human fallback).
   Auto-checks: exactly one of the two carries our AUMID; record the other
   element's `AutomationId`/`Name`/state (running-button signature — any
   localized window-count suffix is informative, never load-bearing);
   **compare the pin's element to its §5.2 baseline — must be unchanged**.
   Human: two separate buttons visible; hovering the running one shows a
   window preview, the pin does not.
5. Auto: close the target gracefully; poll until the count returns to 1;
   the survivor must carry our AUMID; compare to baseline again.

### 5.4 Q3 — teardown demonstration

6. Auto: unpin via S-4's `RemoveFromList` (Start source), wait for the
   pin-folder signal. Zero gestures expected for the entire teardown.

### 5.5 Close-out (when the spike is closed)

7. `Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\PinnedLauncher S9 Spike" -Recurse -Force`
   and `Remove-Item .\out -Recurse -Force`.

## 6. Results

Transcribed from `results\s9-run-20260815-213556.json` (see the §3 runner
note on the two cosmetic `detected: false` fields).

### 6.1 Q1 — pin-alone element

| Property | Value |
|---|---|
| Found (count by name / by AUMID) | exactly 1 |
| `AutomationId` | **`Appid: PinnedLauncher.Test.S9Oracle1`** — the hypothesis holds on our article |
| `Name` | `S9 pin test bloccato` (localized pin suffix — informative only) |
| `ClassName` / control type | `Taskbar.TaskListButtonAutomationPeer` / 50000 (Button) |
| `LegacyIAccessible` state / offscreen | `0x100000` / 0 |
| Visual | exactly one button ✅ |

### 6.2 Q2 — collision, discriminator, invariant

| Check | Result |
|---|---|
| Two buttons while the target runs (auto count / visual) | ✅ auto count 2 within **0.1 s** of launch; visually two separate buttons |
| Exactly one element carries the AUMID | ✅ |
| Running button's `AutomationId` / `Name` / state | `Window: 0x500bd6` / `S9 pin test - 1 finestra in esecuzione` / `0x100000` |
| Pin element unchanged vs baseline (target running) | ✅ **no property changed** — identity, class, state, even position (F-2 invariant holds) |
| After target close: count 1, survivor = AUMID, baseline again | ✅ survivor `Appid: PinnedLauncher.Test.S9Oracle1`, unchanged |
| Hover previews | only the running button showed a window thumbnail ✅ |

### 6.3 Q3 — hygiene

| Item | Result |
|---|---|
| Preflight sweep findings / unpin path form used | sweep ran (5 pins read, AUMIDs decoded from the pinned copies); no leftovers — the copy-path unpin form remains untested (S-4's source form suffices so far) |
| Teardown fully programmatic (gesture count) | **0 gestures**: `RemoveFromList` S_FALSE, pinned copy gone at 0.0 s, UIA button gone (verified by the count-0 poll) |
| Reserved namespace | `PinnedLauncher.Test.*` inaugurated and exercised end-to-end |
| Profile/VM recommendation | spikes ran on the dev profile — acceptable for P0.2; release-gate QTs get a dedicated profile/VM (P2 test plan) |

## 7. Outcome — recorded 2026-08-15

- **The oracle rule, validated for ADR-0009's harness helper.** On the
  Win11 taskbar (family 26200), every task button is a UIA `Button` of
  class `Taskbar.TaskListButtonAutomationPeer`, and its `AutomationId`
  encodes its nature: **`Appid: <AUMID>`** for a pinned entry,
  **`Window: 0x<hwnd>`** for a running window. The QT oracle is therefore:
  *the launcher pin is the element with `AutomationId == "Appid: <launcher
  AUMID>"`; the launched target is a separate `Window:`-prefixed element;
  F-2 holds iff the pin's element persists with identity properties
  unchanged while the target runs.* Verified under the worst case — a
  running window named identically to the pin — where names alone are
  ambiguous by construction; the localized `Name` suffixes (*bloccato*,
  *N finestra in esecuzione*) are never load-bearing. Caveat for the
  harness: the `Appid:`/`Window:` prefixes are undocumented XAML-taskbar
  implementation details — match them prefix-tolerantly (accept the bare
  AUMID too) and treat them as build-family-validated facts, which is
  precisely why ADR-0009 mandates per-family revalidation.
- **The F-2 assertion is fully programmatic.** The pin element was
  byte-identical across pin-alone → target-running → target-closed; the
  NF-8 regression (pin expanding in place) would show as the pin element
  changing or the `Window:` element replacing it — both detectable by the
  same dump-and-compare the runner demonstrated.
- **Hygiene definitions for the P2 test plan.** (1) Reserved test-AUMID
  namespace `PinnedLauncher.Test.*`, disjoint from the product's
  `PinnedLauncher.Proxy.*` — sweeps key on the prefix. (2) Failed-run
  recovery = the demonstrated preflight sweep: enumerate
  `User Pinned\TaskBar\*.lnk`, read each copy's AUMID (the copy retains the
  property store), unpin `PinnedLauncher.*` leftovers programmatically.
  (3) Teardown is gesture-free end-to-end (S-4's `RemoveFromList` +
  artifact deletion), verified down to the UIA tree. (4) Release-gate QTs
  run on a dedicated profile/VM; the taskbar combine mode
  (`TaskbarGlomLevel`) is an environment variable the matrix records and
  varies.
- **Revalidation rule restated:** family-26200 evidence; the oracle
  protocol (this runner) rides along the S-3 confirmation runs on
  26100/28000 and re-runs whenever the C-2 matrix gains a build family
  (ADR-0009).
- Side data: third AppsFolder-indexing datum (3.1 s); the S-4 deep link
  and `RemoveFromList` each confirmed on a fourth/fifth AUMID.
- Design docs updated (2026-08-15): ADR-0009 amendment, TODO.md S-9 item.
