# Spike S-5 — pin-edit propagation: icon/name updates without a re-pin

- Step: [implementation-plan](../implementation-plan.md) P0.2.
- Status: **complete — accepted outcome recorded 2026-08-15 (§7)**; executed via
  the guided runner, raw data in
  `spikes/s5-editprop/results/s5-run-20260815-142223.json`.
- Feeds: [architecture §4.2](../architecture.md#42-editing-a-pinned-launcher-name--icon)
  best-effort enhancement decision (and §9 S-5), [UC-5](../use-cases.md) (the
  re-pin wording), feasibility risk R-3 (stale target icon), the P1 design docs
  (icon-artifact **path-stability rule**, → `docs/design/config-schema.md`),
  TODO post-1.0 icon-freshness watcher.
- Throwaway artifacts: [`spikes/s5-editprop/`](../../spikes/s5-editprop/README.md).

## 1. Mechanism model and questions under test

S-4 established that a pin is the shell's own **copy** of the pinned `.lnk`.
The copy carries its own icon-location field and its own file name. The spike
therefore starts from three hypotheses it is designed to verify or refute:

- **H1** — edits to the source `.lnk` (icon path, file name) cannot reach the
  pin *through the shortcut itself*: the copy is never re-read (Q3 tests this
  directly).
- **H2** — the only propagation channel that avoids rewriting undocumented pin
  storage is **rewriting the icon file in place** at the stable path both
  copies reference (Q1 tests this — it is exactly the product's badge-
  recomposition path: re-extract target icon → recompose badge → overwrite the
  same `.ico`).
- **H3** — the expected obstacle on that channel is icon-cache staleness (the
  cache keys on path, not content); Q1's ladder measures how hard the cache is
  to move with documented nudges.

The questions:

- **Q1 — in-place icon refresh (the product path).** With the pin placed and
  the `.ico` rewritten in place (variant A → B, visually unmistakable), does
  the pinned button update — and what is the smallest nudge that makes it?
  Escalation ladder, one rung at a time, stop at the first flip:

  | Rung | Nudge |
  |---|---|
  | N0 | control — no nudge, observe 30 s |
  | N1 | `SHCNE_UPDATEITEM` on the Start-menu source `.lnk` |
  | N2 | `SHCNE_UPDATEITEM` on the `.ico` file itself |
  | N3 | `SHCNE_UPDATEDIR` on the Start-menu spike folder |
  | N4 | `SHCNE_UPDATEITEM` on the `User Pinned\TaskBar` copy — *policy caveat, §2* |
  | N5 | `SHCNE_UPDATEIMAGE(-1)` — global icon-cache imagelist; watch side effects |
  | N6 | `SHCNE_ASSOCCHANGED` — global, heavier; watch side effects |
  | N7 | `ie4uinit.exe -show` — the shipped icon-cache refresh utility |
  | N8 | Explorer restart — **diagnostic upper bound only, never a product mechanism** |

  N8's diagnostic value: a flip only at N8 = cache staleness beyond documented
  nudges; no flip even at N8 = the icon is baked into pin storage at pin time,
  so no channel exists at all. A localization check (does the *Start* entry
  show the new icon while the button doesn't?) pins down where staleness
  lives; a stability repeat re-runs the winning rung once in the reverse
  direction (B → A).
- **Q2 — name propagation.** Source `.lnk` renamed + `SHCNE_RENAMEITEM`: do
  the button tooltip and the jump-list launcher entry follow? Expected no —
  the label comes from the copy's file name (H1) — which would confirm UC-5's
  re-pin guide for renames.
- **Q3 — mechanism confirmation + path-stability rule.** Point the source at a
  **versioned** icon path (`s5-icon-v2.ico`): the Start entry should update,
  the pin must not (H1). Whatever Q1 finds, this fixes a P1 design rule:
  **regenerated icon artifacts must keep a stable path across regenerations**
  — a versioned-filename scheme would sever even a working Q1 channel. Bonus
  auto-check: the `IShellLink`-based icon edit must preserve the AUMID
  property store (gate G0 re-run on the edited `.lnk`).

## 2. Accepted outcome

Not a go/no-go: the guaranteed regenerate-and-re-pin path (architecture §4.2)
stands whatever happens; this spike only decides whether an automatic-
propagation layer goes on top. The spike closes when Q1–Q3 have recorded
answers and:

- architecture §4.2 records the enhancement decision — **layered** (with the
  exact minimal refresh call) or **rejected** — and §9's S-5 line is resolved;
- the policy line is honored: if the only working rung is N4 (a notify aimed
  at the undocumented pin-storage location) or a global refresh (N5/N6) with
  visible side effects, that trade-off is recorded explicitly before layering;
  N8 never qualifies as a mechanism;
- UC-5 is annotated (soften or keep the re-pin wording) and R-3's mitigation
  is restated as verified ("re-extract on launch/edit" + whichever refresh
  call applies);
- the icon path-stability rule (Q3) is noted for the P1 design docs.

## 3. Environment

Single-machine evidence (family 26200) is acceptable for P0.2, per the S-4
precedent; repeat alongside the S-3 confirmation runs if shell deltas are
suspected.

- Machine: physical, Windows 11 Pro 26200.9168 (25H2 — same image as the S-4
  run), it-IT · Date: 2026-08-15 · Artifacts: repo working tree.
- Baseline (runner preflight): 5 pre-existing pins; gate G0 PASS (independent
  AUMID read-back + ICO header sanity).
- Incidental observation: a Start-menu Programs subfolder holding a **single**
  `.lnk` is flattened in the All-apps view — the entry appears directly, no
  folder (S-4's folder showed because it held two shortcuts). Irrelevant to
  the S-4-decided deep-link pin guide (`shell:AppsFolder\<AUMID>` pre-selects
  the entry), but any Start-navigation instruction must not assume a folder.

## 4. Test articles

One AUMID-stamped proxy shortcut (product mechanism, AUMID
`PinnedLauncher.S5.EditTest1`, target `charmap.exe` — never clicked: icon/name
lifecycle only), generated by
[`New-S5Shortcuts.ps1`](../../spikes/s5-editprop/New-S5Shortcuts.ps1) with
gate G0 (independent AUMID read-back + ICO header sanity). Its icon is a
generated file at a **stable path** (`out\s5-icon.ico`) in two unmistakable
variants — **A**: orange square + green corner badge; **B**: blue circle + red
corner badge (main shape *and* badge change: the full recomposition superset)
— plus a versioned second path (`s5-icon-v2.ico`) for Q3. Probe tool
`s5notify.exe` (one `SHChangeNotify` per invocation) built by
`Build-S5Binaries.ps1`.

## 5. Protocol

**Execution: run `.\Invoke-S5Protocol.ps1`** — a guided runner in the S-4
mold: it automates icon rewrites, notify rungs, shortcut edits, pin-folder
waits, and the AUMID re-check; pauses with one clear instruction per human
gesture; states **what to watch before** each observable step; and writes
every measurement and answer to `results\s5-run-<timestamp>.json` for
transcription into §6. The numbered steps below document what the runner does
and remain the reference if a step must be repeated by hand.

### 5.1 Baseline and Q1 ladder

1. Generate the article (icon = variant A), pin via Start → All apps →
   *PinnedLauncher S5 Spike* → right-click → Pin to taskbar; confirm button
   and Start entry both show variant A.
2. Rewrite `s5-icon.ico` **in place** to variant B. Nothing else.
3. Climb rungs N0…N8 one at a time (§1 table), observing the button ~15–30 s
   per rung; stop at the first flip. Record latency, partial effects (hover
   flyout vs button), and side effects (N5/N6: system-wide icon flicker) per
   rung.
4. Localization check: does the Start entry show variant B now?
5. Stability repeat: icon back to variant A, re-run only the winning rung,
   confirm the flip back (skipped if nothing won or only N8 did).

### 5.2 Q2 — name

6. Note the button's tooltip. Rename the source `.lnk` (`S5 edit test` →
   `S5 renamed test`) + `SHCNE_RENAMEITEM`; after ~15 s read the tooltip and
   the jump-list entry name; contrast with the Start entry (expected to show
   the new name). Rename back.

### 5.3 Q3 — versioned path

7. Snapshot what Start entry and button currently show. Write
   `s5-icon-v2.ico` in the *opposite* variant of the current one, point the
   source `.lnk` at it (`IShellLink::SetIconLocation` on the loaded link) +
   `SHCNE_UPDATEITEM`; auto-verify the AUMID survived the edit; record
   whether Start flipped (expected yes) and whether the button did (expected
   no). Restore the stable icon path.

### 5.4 Cleanup

8. Unpin — programmatic via the S-4-validated `RemoveFromList` when
   `spikes/s4-pinflow/bin/s4unpin.exe` is present (bonus second-AUMID data
   point), else the guided gesture. When the spike closes:
   `Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\PinnedLauncher S5 Spike" -Recurse -Force`
   and `Remove-Item .\out -Recurse -Force`.

## 6. Results

### 6.1 Q1 — escalation ladder

Icon rewritten in place A → B before rung N0; ~15–30 s observation per rung,
each rung cumulative on the previous ones.

| Rung | Nudge | Button updated? | Notes |
|---|---|---|---|
| N0 | control (none) | ❌ | |
| N1 | UPDATEITEM source `.lnk` | ❌ | |
| N2 | UPDATEITEM `.ico` | ❌ | |
| N3 | UPDATEDIR Start folder | ❌ | |
| N4 | UPDATEITEM pinned copy | ❌ | the policy-caveated rung didn't work either |
| N5 | UPDATEIMAGE(-1) | ❌ | no side effects reported |
| N6 | ASSOCCHANGED | ❌ | |
| N7 | `ie4uinit -show` | ❌ | |
| N8 | Explorer restart (diagnostic) | ✅ **flipped to B** | proves the icon is *not* baked into pin storage — the shell re-reads the `.ico` path on rebuild |

- Start-entry localization check: showed variant B — but recorded **after**
  N8, so it doesn't localize independently; Q3 (§6.3) supplies the
  localization instead: the All-apps entry does not track icon changes live
  either.
- Stability repeat: skipped by design — only the diagnostic rung flipped, and
  it never qualifies as a mechanism.

### 6.2 Q2 — name propagation

| Observable | Before | After rename + RENAMEITEM |
|---|---|---|
| Button tooltip | `S5 edit test` (JSON records "S4 edit test" — transcription slip; no S4 article existed on the machine) | `S5 edit test` — unchanged |
| Jump-list launcher entry | `S5 edit test` | unchanged |
| Start All-apps entry name | `S5 edit test` | **also unchanged** within the window — even the source's own entry lagged |

### 6.3 Q3 — versioned icon path

Executed in the post-N8 state (everything showing variant B); v2 file =
variant A.

| Check | Result |
|---|---|
| Start entry flipped to the v2 variant | ❌ not within the ~15 s window — the All-apps list renders through the same cache |
| Taskbar button unchanged | ✅ unchanged (structurally guaranteed: the pinned copy still carries the old icon path) |
| AUMID preserved through the icon edit (G0 re-check) | ✅ PASS |

- Cleanup bonus data point: `RemoveFromList` against the Start-menu source
  unpinned the S5 article too — hr = S_FALSE (success class), pinned copy gone
  at first poll (0.0 s) — confirming S-4's Q3 finding on a second AUMID.

## 7. Outcome — recorded 2026-08-15

- **Q1 decision — enhancement rejected.** An in-place rewrite of the badged
  `.ico` (exactly the product's badge-recomposition path) does not reach the
  pinned button — nor even the Start entry — under any documented nudge:
  `SHCNE_UPDATEITEM` on the source `.lnk`, the `.ico`, and the pinned copy,
  `SHCNE_UPDATEDIR`, `SHCNE_UPDATEIMAGE(-1)`, `SHCNE_ASSOCCHANGED`, and
  `ie4uinit -show` all failed. Only an Explorer restart refreshed it, which
  simultaneously proves the icon is **not** baked into pin storage: the
  staleness is icon-cache-level, with no documented invalidation reaching
  taskbar buttons. No reliable, low-risk mechanism exists → the architecture
  §4.2 **guaranteed regenerate-and-re-pin path stands alone**; §2's policy
  weighing (N4-only / global-rung-only scenarios) never arose. Risk R-3
  restated: a stale target icon is corrected on edit via regenerate + guided
  re-pin, and heals passively at the next Explorer session; no silent live
  refresh exists.
- **Q2 statement — renames need the re-pin.** Neither the button tooltip nor
  the jump-list entry followed the source rename + `SHCNE_RENAMEITEM`; even
  the Start All-apps entry kept the old name within the observation window.
  UC-5's guided unpin → re-pin stands as the flow, not a fallback.
- **Q3 design rule — stable icon path.** Icon-location edits on the source
  don't propagate anywhere live, and the pinned copy retains the original
  icon path forever. Regenerated icon artifacts must therefore keep a
  **stable path**: an in-place rewrite leaves an existing pin at worst
  temporarily stale and lets it heal at the next Explorer session, whereas a
  versioned filename (old file deleted) would permanently break the pin's
  icon. Bonus for the product edit path: the `IShellLink`-based icon edit
  preserves the AUMID property store (G0 re-check PASS).
- Design docs updated (2026-08-15): architecture §4.2, use-cases.md UC-5,
  TODO.md S-5 item + post-1.0 icon-watcher item.
