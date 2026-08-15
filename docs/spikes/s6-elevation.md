# Spike S-6 — elevation semantics: `runas` on the resolved target + confused-deputy guard

- Step: [implementation-plan](../implementation-plan.md) P0.2.
- Status: **complete — accepted outcome recorded 2026-08-15 (§7)**; executed
  via the guided runner, raw data in
  `spikes/s6-elevation/results/s6-run-20260815-160212.json` (plus the aborted
  first attempt `s6-run-20260815-154930.json`, kept as the §7 indexing-lag
  evidence).
- Feeds: [UC-6](../use-cases.md) (the **normative** modified-launch semantics —
  both of its "verified in spike S-6" hooks), [architecture
  §4](../architecture.md#4-shared-core) launch-service elevation rule and §9's
  S-6 line, F-8/F-9 (run-as-admin property and jump-list task), feasibility
  risk R-4 (double UAC / lingering proxy button), the P1 design docs
  (`docs/design/cli.md` `--launch <slug> --elevated` contract,
  `docs/design/modules.md` guard predicate).
- Throwaway artifacts: [`spikes/s6-elevation/`](../../spikes/s6-elevation/README.md).

## 1. Mechanism model and questions under test

Elevation touches the design on two disjoint paths (UC-6):

- **Supported** — per-launcher elevated launch: a **medium-integrity** process
  (the per-click proxy; in the product also `PinnedLauncher.exe --launch
  <slug> --elevated` behind the jump-list task — same mechanism, same
  process class) applies the `runas` verb to the **resolved target**, so the
  UAC prompt names the actual program being elevated, never the proxy.
- **Unsupported** — the shell's native elevate-the-pin gesture
  (Ctrl+Shift+click), which elevates *the proxy itself*. An elevated generic
  proxy that then executes config-derived commands would be a **confused
  deputy**; the design mandates detect-and-refuse.

The questions:

- **Q1 — supported-path UX (risk R-4).** From a plain click on the pin, the
  medium-IL proxy launches the config-resolved target with `runas`. Verify:
  - exactly **one** UAC prompt (no double consent anywhere in the chain);
  - the prompt **names the target** — the unsigned test target by file name
    with the unknown-publisher banner, a signed OS binary by its verified
    name (both recorded);
  - the target genuinely runs elevated — the self-reporting oracle: the
    target logs its own token facts, no eyeballing;
  - **no proxy taskbar button at any point** — the windowless proxy stays
    alive only while consent is pending (`SEE_MASK_NOASYNC` blocks inside
    `ShellExecuteEx`), and a windowless process should surface no button;
  - the elevated target opens as its **own** button, not merged into the pin
    (the S-3 invariant, extended to the elevated case);
  - UAC **cancel** → `ShellExecuteEx` fails with `ERROR_CANCELLED` (1223),
    the proxy exits silently — no shell error UI, nothing lingers.
- **Q2 — elevated-start vectors.** Which native routes actually start the
  proxy elevated, so the guard's trigger surface is known:
  - **Ctrl+Shift+click** on the pin (the gesture UC-6 names);
  - the jump list's own context menu on the entry name — *Esegui come
    amministratore*, if the shell offers it there at all (existence is itself
    a finding);
  - the programmatic **`RunAs` verb** on the proxy exe — the repeatable
    regression form, runner-automated. A child inheriting an elevated
    parent's token carries the same signature, so one programmatic form
    suffices.
- **Q3 — detection signal + refusal path.** Which token facts cleanly
  separate an elevated start from the normal one: `TokenElevation`,
  `TokenElevationType`, and the integrity level are all logged on every run
  of both executables (automatic collection — §6.3's matrix falls out of the
  logs). The elevated proxy must refuse **before the config file is even
  opened**, explain the supported alternative, and exit leaving nothing
  behind. Output: the guard predicate for P1.
  **Bounded residual** (design note — not testable here without machine
  reconfiguration): UAC-off and built-in-Administrator sessions run
  *everything* elevated (`TokenElevationTypeDefault` + high IL); the P1
  predicate must not brick such sessions — and there the medium-IL boundary
  the guard protects does not exist in the first place. Candidate predicate
  to weigh in P1 with this spike's data: refuse iff
  `TokenElevationTypeFull`.

## 2. Accepted outcome

Not a strict go/no-go, but Q1 carries risk R-4: a double UAC, a prompt naming
the proxy, or a lingering button would invalidate UC-6's implementation rule
as written and would need a mitigation folded into the design (or a descope
decision) before P1. The spike closes when Q1–Q3 have recorded answers and:

- UC-6's two verification hooks become true, dated annotations (elevated
  launch rule; guard behavior and detection);
- architecture §9's S-6 line is resolved and §4's elevation rule annotated
  as verified;
- R-4 is restated as verified (or its mitigation redesigned);
- the guard predicate decision — with the UAC-off design note — is recorded
  for the P1 design docs (`cli.md`, `modules.md`);
- policy line held: only documented APIs (`ShellExecuteEx`/`runas`,
  `GetTokenInformation`) — no undocumented elevation or token tricks.

## 3. Environment

Single-machine evidence (family 26200) is acceptable for P0.2, per the S-4/S-5
precedent; repeat alongside the S-3 confirmation runs if shell deltas are
suspected.

- Machine: physical, Windows 11 Pro 26200.9168 (25H2 — same image as the S-4
  and S-5 runs), it-IT · Date: 2026-08-15 · Artifacts: repo working tree.
- Baseline (runner preflight): 5 pre-existing pins; gate G0 PASS (independent
  AUMID read-back + config/target sanity); the runner enforces a medium-IL
  console before starting.
- Two-run history: the first run aborted at the pin step — the S-4 deep link
  hit `0x80070002` (`SHParseDisplayName`) because a **freshly installed Start
  entry is not immediately indexed in `shell:AppsFolder`** (~28 s after
  install; stub JSON kept as evidence). The runner gained an indexing poll;
  the second run found the AUMID already indexed (0.0 s — the generator's
  delete-and-recopy of an already-indexed entry did not evict it), the deep
  link succeeded (all HRESULTs S_OK, entry pre-selected — third-AUMID
  re-validation of the S-4-decided guide), and the protocol completed
  end-to-end.

## 4. Test articles

| Piece | Role |
|---|---|
| `bin\s6proxy.exe` | Windowless proxy (product mechanism): queries its own token **first**, refuses if elevated (the guard — the config file is never opened on that path), else reads the target from `out\s6config.txt` and applies `runas` to it. Every decision appends one parseable line to `out\s6-proxy-log.txt`. Exit codes: 0 launched · 1 UAC cancelled · 2 config missing · 3 refused (elevated start) · 4 other failure |
| `bin\s6target.exe` | Self-reporting target: logs its own token facts to `out\s6-target-log.txt`, then holds a message box open so the taskbar button can be observed. Unsigned → the UAC prompt shows the file name + unknown-publisher banner |
| `out\s6config.txt` | The config-derived command (target path) — the confused-deputy surface. The runner swaps it to `regedit.exe` for the signed-naming check (S-C) and restores it |
| Proxy shortcut | `S6 elevation test.lnk` → `bin\s6proxy.exe`, AUMID `PinnedLauncher.S6.ElevTest1`, installed under `Start Menu\Programs\PinnedLauncher S6 Spike`. Gate **G0**: independent AUMID read-back + config/target sanity |

Log line format (both logs, one line per run):
`ts=<iso> pid=<n> exe=<name> elevated=<0|1> type=<Default|Full|Limited> integrity=<Low|Medium|High|System> rid=0x<hex> action=<LAUNCHED|CANCELLED|REFUSED|RUNNING|NOCONFIG|ERROR> detail=<win32 err>`

Pin-route note: a single-`.lnk` Start-menu spike folder is flattened in the
All-apps view (S-5 observation); the runner pins via the S-4-decided deep link
(`s4select.exe` on `shell:AppsFolder\<AUMID>`) when available, which sidesteps
navigation entirely — a bonus re-validation of the decided pin guide. The
runner first polls `ParseName(<AUMID>)` on `shell:AppsFolder`: a freshly
installed Start entry is **not** immediately parseable there (first-attempt
evidence in §3/§7).

## 5. Protocol

**Execution: run `.\Invoke-S6Protocol.ps1`** — a guided runner in the S-4/S-5
mold: it automates builds, article generation, config swaps, log polling with
automatic expectation checks, and the programmatic-RunAs scenario; pauses with
one clear instruction per human gesture; states **what to watch before** each
observable step; and writes every measurement and answer to
`results\s6-run-<timestamp>.json` for transcription into §6. The numbered
steps below document what the runner does and remain the reference if a step
must be repeated by hand.

### 5.1 Baseline pin

1. Generate the article (gate G0); **wait for `shell:AppsFolder` to index
   the AUMID** (poll `ParseName`, latency recorded — a freshly installed
   entry is not immediately parseable, §7); then pin: deep link via
   `..\s4-pinflow\bin\s4select.exe PinnedLauncher.S6.ElevTest1` → right-click
   the pre-selected entry → Pin to taskbar (fallback: Start → All apps —
   the entry sits directly in the list, no folder). Confirm via the
   synchronous `User Pinned\TaskBar` signal (S-4).

### 5.2 Q1 — supported elevated launch (S-A, S-B, S-C)

2. **S-A — launch + accept.** Watch, in order: the exact program name on the
   UAC dialog; the number of prompts; the taskbar for any transient new
   button while consent is pending. Click the pin once, accept. The runner
   reads both logs: proxy expected `elevated=0 action=LAUNCHED`, target
   expected `elevated=1 integrity=High action=RUNNING`. Observe: the target's
   message box has its **own** taskbar button, separate from the pin. Close
   the target.
3. **S-B — launch + cancel.** Click the pin, **cancel** the UAC. Runner
   expects `action=CANCELLED detail=1223`. Observe: no error dialog, nothing
   lingers on the taskbar.
4. **S-C — signed-target naming.** Runner points the config at
   `regedit.exe`. Click the pin, **read the UAC dialog** (name + verified
   publisher line), then **cancel** — the naming datum needs no launch, and
   regedit never opens. Runner restores the config.

### 5.3 Q2/Q3 — the guard (S-D, S-E, S-F)

5. **S-D — Ctrl+Shift+click.** This elevates the *proxy* — the exact vector
   the guard exists for. Watch: the UAC should now name `s6proxy.exe`;
   accept deliberately. Expected: the refusal message appears, the target
   does **not** start. Runner checks `elevated=1 action=REFUSED` and that
   the target log did not grow. Close the refusal; observe: no residue.
6. **S-E — jump-list context menu.** Right-click the pin → right-click the
   entry name in the jump list. Record whether *Esegui come amministratore*
   is offered at all; if yes, invoke it and repeat S-D's checks.
7. **S-F — programmatic RunAs (automated).** The runner itself starts
   `s6proxy.exe` with the `RunAs` verb; accept the UAC. Same checks as S-D —
   this is the repeatable regression form of the guard.
8. The runner prints and records the **token matrix** (§6.3) assembled from
   all scenario logs — the Q3 detection-signal answer.

### 5.4 Cleanup

9. Unpin — programmatic via S-4's `s4unpin.exe` when present (bonus AUMID
   data point), else the guided gesture.
10. When the spike closes:
    `Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\PinnedLauncher S6 Spike" -Recurse -Force`
    and `Remove-Item .\out -Recurse -Force`.

## 6. Results

Transcribed from `results\s6-run-20260815-160212.json`; every automated
expectation check the runner performed passed.

### 6.1 Q1 — supported path

| Scenario | UAC prompts | UAC names | Proxy log | Target log | Button observations |
|---|---|---|---|---|---|
| S-A launch + accept | **1** | `s6target.exe` (unsigned — file name shown) | `elevated=0 type=Limited integrity=Medium action=LAUNCHED` | `elevated=1 type=Full integrity=High action=RUNNING` | target window got its **own** button, separate from the pin (no merge) |
| S-B launch + cancel | 1 (declined) | — | `action=CANCELLED detail=1223` (`ERROR_CANCELLED`) | — (not launched) | no error dialog, nothing lingering |
| S-C signed naming (cancelled) | 1 (declined) | *Editor del Registro di sistema* · *Autore verificato: Microsoft Windows* | `action=CANCELLED detail=1223` | — (regedit never opened) | — |

**Secure-desktop note.** The "transient proxy button while the UAC is open"
observation was recorded as *skipped*: the consent prompt runs on the secure
desktop, which freezes and dims the interactive desktop — the taskbar is not
visible during consent. That makes the question **moot by construction** for
the user experience too (no user can see the taskbar in that state); R-4's
button concern is answered by the observable before/after states, which were
clean in every scenario.

### 6.2 Q2 — elevated-start vectors + guard behavior

| Vector | Starts the proxy elevated? | UAC names | Guard verdict (log) | Target untouched | Residue after refusal |
|---|---|---|---|---|---|
| S-D Ctrl+Shift+click | ✅ | `s6proxy.exe` | `elevated=1 type=Full integrity=High action=REFUSED`; refusal message shown | ✅ (target log unchanged) | none |
| S-E jump-list context menu | ✅ — ***Esegui come amministratore* is offered** on the entry name | *(same consent flow; not separately recorded)* | `elevated=1 type=Full integrity=High action=REFUSED`; refusal message shown | ✅ | — |
| S-F programmatic `RunAs` | ✅ | `s6proxy.exe` | `elevated=1 type=Full integrity=High action=REFUSED`; logged 0.22 s after consent | ✅ | — |

### 6.3 Q3 — token matrix (from the logs)

| Scenario | exe | elevated | type | integrity | action |
|---|---|---|---|---|---|
| S-A proxy | s6proxy | 0 | Limited | Medium | LAUNCHED |
| S-A target | s6target | 1 | Full | High | RUNNING |
| S-B proxy | s6proxy | 0 | Limited | Medium | CANCELLED |
| S-D proxy | s6proxy | 1 | Full | High | REFUSED |
| S-E proxy | s6proxy | 1 | Full | High | REFUSED |
| S-F proxy | s6proxy | 1 | Full | High | REFUSED |

- Cleanup bonus data point: `RemoveFromList` against the Start-menu source
  unpinned the S6 article too — hr = S_FALSE (success class), pinned copy
  gone at first poll (0.0 s) — confirming S-4's Q3 finding on a third AUMID.

## 7. Outcome — recorded 2026-08-15

- **Q1 — supported path verified; risk R-4 cleared.** A plain click on the
  pin produced exactly **one** UAC prompt naming the **resolved target**:
  the unsigned target by file name with the unknown-publisher banner, the
  signed OS binary by its verified display name (*Editor del Registro di
  sistema*, *Autore verificato: Microsoft Windows*). The target genuinely
  ran elevated (its own token log: full token, high IL) and opened as its
  own taskbar button — the S-3 non-merge invariant holds under elevation.
  Declining the prompt ends in a silent `ERROR_CANCELLED` (1223) exit: no
  error UI, no residue. No double UAC, no proxy-named prompt, no lingering
  button — R-4 restated as verified: windowless proxy + `runas` on the
  resolved target behaves exactly as designed. UC-6's implementation rule
  and architecture §4's elevation rule annotated.
- **Q2 — the guard's trigger surface is real and fully covered.** All three
  vectors start the proxy elevated and were detected and refused:
  Ctrl+Shift+click (UAC names `s6proxy.exe`); the jump list **does** offer
  *Esegui come amministratore* on the entry name — the vector exists, so the
  guard is not optional; and the programmatic `RunAs` verb (the repeatable
  regression form). In every case the refusal message appeared, the config
  was never consumed (the target log never grew), and nothing lingered.
- **Q3 — detection predicate for P1.** The matrix separates perfectly:
  every medium start is `elevated=0 / Limited / Medium`, every elevated
  start is `elevated=1 / Full / High` — `TokenElevation` alone suffices on
  this configuration, and `TokenElevationTypeFull` co-occurred with every
  elevated start. **P1 recommendation: refuse iff the token's elevation
  type is `Full`** — equivalent here, and it degrades correctly in the
  untested UAC-off / built-in-Administrator residual (§1): those sessions
  report type `Default`, so the guard never fires where no medium-IL
  boundary exists to protect. The refusal MessageBox displays fine from the
  windowless elevated proxy, and guard-before-config-read is verified
  behaviorally (untouched target log), not just by construction.
- **Side finding — `shell:AppsFolder` indexing lag (feeds the pin guide).**
  A freshly installed Start-menu entry is not immediately parseable in
  `shell:AppsFolder`: the first run's deep link failed with `0x80070002`
  ~28 s after install, while minutes later the entry resolved and re-copying
  it did not evict it. The product's pin guide opens the Apps view right
  after creating a launcher — exactly this window — so it must poll
  `ParseName(<AUMID>)` until the entry appears before offering the
  deep-link button (management-window §5.3 annotated; the runner's poll is
  the reference implementation).
- Design docs updated (2026-08-15): use-cases.md UC-6, architecture.md §4,
  management-window.md §5.3, TODO.md S-6 item.
