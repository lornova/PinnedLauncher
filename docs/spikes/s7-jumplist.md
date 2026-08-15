# Spike S-7 — jump-list tasks on a proxy AUMID with no process running

- Step: [implementation-plan](../implementation-plan.md) P0.2.
- Status: **complete — accepted outcome recorded 2026-08-15 (§7)**; executed
  via the guided runner, raw data in
  `spikes/s7-jumplist/results/s7-run-20260815-201556.json`.
- Feeds: [UC-7](../use-cases.md) (the launcher context menu),
  [architecture §4.1](../architecture.md#41-per-launcher-right-click-menu-jump-list-tasks)
  (the publisher mechanism, the planned task menu, `DeleteList` on removal)
  and §9's S-7 line, F-9 (Should), [management-window
  §5.2](../management-window.md) (capability-matrix-gated tasks — mechanism
  only here), release 0.5.0 (the jump-list publisher increment).
- Throwaway artifacts: [`spikes/s7-jumplist/`](../../spikes/s7-jumplist/README.md).

## 1. Mechanism model and questions under test

Every proxy pin has its own AUMID, so every launcher can get its own menu:
the management app calls `ICustomDestinationList` — `SetAppID(<AUMID>)` →
`BeginList` → `AddUserTasks` → `CommitList` — at launcher creation/edit, and
`DeleteList` at removal (architecture §4.1). Microsoft documents that tasks
are available **even when the application is not running** — exactly a pure
launcher pin's state. This spike converts that documented claim into
evidence, in the product's own usage order (list committed **before** the
pin exists, since the creation pipeline runs before the user's pin gesture).

- **Q1 — render with no process running.** A task list (three tasks + one
  separator via `System.AppUserModel.IsDestListSeparator` — the §4.1 menu
  needs separators) committed for the proxy AUMID *before pinning*: after
  the pin gesture, does right-clicking the pin show the tasks — with no
  process of ours alive (auto-verified)? Do they sit in a Tasks section
  above the system entries (launch name, unpin), per §4.1's documented
  bounds?
- **Q2 — tasks invoke our exe with their arguments.** Clicking a task must
  start the task's target with the stored arguments (the product's tasks
  are `PinnedLauncher.exe --edit <slug>` etc. — arguments are mandatory
  for jump-list tasks). Oracle: the task target is a self-reporting echo
  tool logging its argv; the runner polls the log.
- **Q3 — update and delete lifecycles.** Re-committing a modified list
  (a task renamed with new args, one task and the separator dropped) must
  update the menu — the §4.1 edit path; `DeleteList` must remove the Tasks
  section entirely (system entries remain) — the removal/uninstall path.

## 2. Accepted outcome

A quick sanity check, not a go/no-go: the mechanism is documented and the
architecture already cites the documentation; this spike records evidence on
a supported build. It closes when Q1–Q3 have recorded answers and:

- architecture §4.1 is annotated verified (or, on failure, F-9 — a Should —
  gets a mitigation/descope decision: reduced menu or management via the
  window only);
- UC-7 is annotated with the verification date;
- the §6.1 API HRESULT trace is on record for the P1 publisher design.

Single-machine evidence (family 26200) is acceptable for P0.2 per the
S-4..S-6 precedent; the other C-2 families ride along the S-3 confirmation
runs.

## 3. Environment

- Machine: physical, Windows 11 Pro 26200.9168 (25H2 — same image as the
  S-4..S-6 runs), it-IT · Date: 2026-08-15 · Artifacts: repo working tree.
- Baseline (runner preflight): 5 pre-existing pins; gate G0 PASS (independent
  AUMID read-back + binaries present).
- Pin flow: the fresh Start entry became parseable in `shell:AppsFolder`
  after **3.0 s** of polling — a second, tighter datum for the S-6 indexing
  finding (S-6's first fresh entry was still unindexed at ~28 s); the poll
  absorbs the variance either way. Deep link all S_OK with the entry
  pre-selected (third run of the S-4-decided guide, third AUMID).

## 4. Test articles

| Piece | Role |
|---|---|
| `bin\s7jumplist.exe` | Console tool around `ICustomDestinationList`, one HRESULT printed per API step: `commit` (initial list: *S7 Alpha task*·`alpha`, *S7 Beta task*·`beta`, separator, *S7 Gamma task*·`gamma`), `commit2` (edited list: *S7 Alpha task v2*·`alpha2`, *S7 Gamma task*·`gamma` — rename + drops), `delete` (`DeleteList`) |
| `bin\s7taskecho.exe` | Windowless task target: appends `ts=… pid=… exe=s7taskecho args=<argv>` to `out\s7-task-log.txt` and exits — the Q2 oracle (task args are single-token by design so the key=value log stays parseable) |
| Proxy shortcut | `S7 jumplist test.lnk` → `bin\s7taskecho.exe`, AUMID `PinnedLauncher.S7.JumpTest1`, installed under `Start Menu\Programs\PinnedLauncher S7 Spike`. Gate **G0**: independent AUMID read-back + binaries present. The pin itself is never clicked (jump-list lifecycle only; an accidental click logs an empty-args line, distinguishable from every task) |

Pin-route note (S-6 findings): the runner polls `ParseName(<AUMID>)` on
`shell:AppsFolder` before deep-linking (fresh Start entries are not
immediately parseable), then pins via the S-4-decided
`SHOpenFolderAndSelectItems` deep link; single-`.lnk` spike folders are
flattened in the All-apps fallback route (S-5).

## 5. Protocol

**Execution: run `.\Invoke-S7Protocol.ps1`** — a guided runner in the
S-4..S-6 mold: it automates builds, article generation, every
`ICustomDestinationList` call, the no-process check, and log polling with
automatic expectation checks; pauses with one clear instruction per human
gesture; states **what to watch before** each observable step; and writes
every measurement and answer to `results\s7-run-<timestamp>.json` for
transcription into §6. The numbered steps below document what the runner
does and remain the reference if a step must be repeated by hand.

### 5.1 Baseline: commit before pin, then pin

1. Generate the article (gate G0). **Commit the initial task list now** —
   before any pin exists, the product's creation order.
2. Wait for `shell:AppsFolder` to index the AUMID, then pin via the deep
   link (fallback: Start → All apps, entry sits directly in the list).
   Confirm via the synchronous `User Pinned\TaskBar` signal (S-4).

### 5.2 Q1 — render with no process running

3. Auto-check: no `s7jumplist`/`s7taskecho` process alive. Right-click the
   S7 pin. Observe: Tasks section present with *S7 Alpha task*, *S7 Beta
   task*, a separator, *S7 Gamma task*; tasks above the system entries;
   note the section header text.

### 5.3 Q2 — task invocation

4. Click *S7 Alpha task* in the jump list. The runner polls the task log:
   expected `exe=s7taskecho args=alpha`. Note any side observations
   (window flash etc.).

### 5.4 Q3 — update and delete

5. Runner re-commits the edited list (`commit2`). Right-click again:
   expected *S7 Alpha task v2* and *S7 Gamma task* only — Beta and the
   separator gone.
6. Click *S7 Alpha task v2*: expected `args=alpha2` (the updated arguments
   flow through).
7. Runner calls `delete` (`DeleteList`). Right-click again: expected no
   Tasks section at all; the system entries remain.

### 5.5 Cleanup

8. Unpin — programmatic via S-4's `s4unpin.exe` when present, else the
   guided gesture.
9. When the spike closes:
   `Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\PinnedLauncher S7 Spike" -Recurse -Force`
   and `Remove-Item .\out -Recurse -Force`.

## 6. Results

Transcribed from `results\s7-run-20260815-201556.json`; every automated
expectation check the runner performed passed.

### 6.1 Q1 — render with no process running

| Check | Result |
|---|---|
| API trace (`commit`, pre-pin) | all 12 steps S_OK (`SetAppID` → `BeginList` → 3 tasks + separator → `AddUserTasks` → `CommitList`) |
| No process of ours alive at observation (auto) | ✅ 0 processes |
| Tasks render on the pin's jump list | ✅ all three (*Alpha*, *Beta*, *Gamma*) |
| Separator renders between Beta and Gamma | ✅ |
| Tasks above the system entries; section header | ✅ above; header **"Attività"** |

### 6.2 Q2 — task invocation

| Click | Expected log | Observed | Notes |
|---|---|---|---|
| *S7 Alpha task* | `exe=s7taskecho args=alpha` | ✅ exact match | nothing visible on click (windowless target — no flash) |
| *S7 Alpha task v2* (post-update) | `args=alpha2` | ✅ exact match | the updated arguments flow through |

### 6.3 Q3 — update and delete

| Step | Expected | Observed |
|---|---|---|
| `commit2` re-commit | menu shows *Alpha v2* + *Gamma* only | ✅ exact; no staleness, no delay reported |
| `DeleteList` | Tasks section gone; system entries remain | ✅ |

- Cleanup bonus data point: `RemoveFromList` against the Start-menu source —
  hr = S_FALSE (success class), pinned copy gone at first poll (0.0 s) —
  confirming S-4's Q3 finding on a **fourth** AUMID.

## 7. Outcome — recorded 2026-08-15

- **Q1 — the documented claim is now evidence.** A task list committed for
  the proxy AUMID **before any pin existed** (the product's creation order)
  renders on the pin's jump list with zero processes of ours alive: the
  list is keyed to the AUMID and attaches to the pin whenever the pin
  appears. Separators (`System.AppUserModel.IsDestListSeparator`) render;
  tasks sit above the system entries under the localized *Attività* header
  — matching §4.1's documented bounds exactly.
- **Q2 — tasks invoke our exe with their stored arguments.** Both the
  original and the post-update task launched the windowless target with the
  exact stored argument (log-oracle verified), with nothing visible on
  click. The product's task pattern — `PinnedLauncher.exe --edit <slug>`
  etc. — rests on verified ground.
- **Q3 — the full publisher lifecycle works.** Re-committing a modified
  list replaced the menu immediately (rename + dropped entries, no
  staleness observed); `DeleteList` removed the Tasks section entirely,
  leaving the system entries. Creation, edit, and removal — the three §4.1
  paths — are all verified with a complete S_OK API trace on 26200.
- F-9's mechanism is de-risked for the 0.5.0 increment; the P1 publisher
  design can adopt the traced call sequence as-is.
- **Side datum:** the fresh Start entry became `shell:AppsFolder`-parseable
  after 3.0 s of polling — second data point for the S-6 indexing-lag
  finding (first fresh entry: still unindexed at ~28 s); the
  management-window §5.3 poll-before-deep-link rule stands, and the
  latency evidently varies.
- Design docs updated (2026-08-15): use-cases.md UC-7, architecture.md
  §4.1, TODO.md S-7 item.
