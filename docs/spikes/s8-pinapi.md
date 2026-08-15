# Spike S-8 — `TaskbarManager` pin-API evaluation

- Step: [implementation-plan](../implementation-plan.md) P0.2.
- Status: **complete — accepted outcome recorded 2026-08-15 (§7)**;
  executed via the guided runner, raw data in
  `spikes/s8-pinapi/results/s8-run-20260815-225511.json` plus the two
  post-run recheck fact files beside it (§6.4).
- Feeds: [architecture §5](../architecture.md) (the setup flow — whether the
  manual pin gesture is replaced, layered, or kept), architecture §8.1 (the
  servicing-gated LAF row — confirm or amend), the pin-guide UX (0.4.0),
  [feasibility §3](../feasibility.md) item 2's open evaluation, TODO.md's
  S-8 item.
- Throwaway artifacts: [`spikes/s8-pinapi/`](../../spikes/s8-pinapi/README.md).

## 1. Mechanism model and questions under test

`Windows.UI.Shell.TaskbarManager` exposes consent-gated pin-request APIs.
If one of them works from our **unpackaged** exe and can target our
**generated Start entries** (proxy `.lnk` + explicit AUMID), the §5 manual
pin gesture shrinks to a consent dialog. Desk research (2026-08-15, against
Microsoft's [pin-to-taskbar page](https://learn.microsoft.com/windows/apps/develop/windows-integration/pin-to-taskbar)
as updated 2026-07-16, the
[`TaskbarManager` reference](https://learn.microsoft.com/uwp/api/windows.ui.shell.taskbarmanager),
and the official
[desktop sample](https://github.com/microsoft/Windows-classic-samples/tree/main/Samples/TaskbarManager))
sharpened the architecture-§9 question into **three routes**:

- **Route A — `RequestPinCurrentAppAsync`.** Microsoft's *unpackaged*
  desktop sample (`CppUnpackagedDesktopTaskbarPin`) does exactly what our
  product does: it writes an AUMID-stamped Start-menu `.lnk`, sets the
  **process-explicit AUMID** (`SetCurrentProcessExplicitAppUserModelID`),
  and calls `RequestPinCurrentAppAsync` — "current app" is whatever
  identity the process carries. Composed with our per-launcher AUMIDs,
  a short-lived helper process that assumes the launcher's AUMID could
  request a pin for **any** generated entry. This is the primary route.
  Documented preconditions: app in **foreground**, a matching **Start
  menu entry**, consent dialog per request; already-pinned requests
  return `true` immediately with no dialog.
- **Route B — `RequestPinAppListEntryAsync`.** The API named in
  architecture §9. Research finding: its `AppListEntry` parameter has **no
  documented acquisition path for unpackaged apps** — the only documented
  producers are `Package.GetAppListEntries[Async]` (SDK 26100 projection
  confirms: only `IPackage3/IPackage8` yield `AppListEntry`), and
  `AppInfo.GetFromAppUserModelId` yields an `AppInfo`, not an entry. The
  spike verifies the dead end empirically on our AUMID and, as a control,
  exercises the full route on a *packaged* AUMID (Calculator/Notepad/
  Settings, first indexed) — proving whether the API itself works when
  called **from** our unpackaged process, independent of what it can
  target. The control dialog is answered **No**, so it leaves no pin.
- **Route C — secondary tiles** (`RequestPinSecondaryTileAsync`,
  `IsSecondaryTilePinnedAsync`, `TryUnpinSecondaryTileAsync`).
  `SecondaryTile` is package-identity infrastructure, and the reference
  still marks the pin request as LAF-gated even after the KB below.
  Expected to fail from an unpackaged caller; the exact failure stage and
  HRESULTs are recorded, closing the "secondary-tile pin/update/unpin"
  clause of architecture §9.

**LAF/servicing state (§8.1).** Taskbar pinning was a Limited Access
Feature; the restriction's removal began with
[KB5074105](https://support.microsoft.com/topic/85bd25de-894a-43eb-a19b-9a59d10f194b)
(26x00.7705, Jan 2026). Microsoft documents a runtime registry probe —
`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\LimitedAccessFeatures\com.microsoft.windows.taskbar.pin`,
seed value `4096B2…53D4`: token required iff the value exists and is
non-zero — plus the `ITaskbarManagerDesktopAppSupportStatics` marker on
the activation factory for desktop-app support. `s8pin.exe probe`
implements both verbatim, alongside `IsSupported`/`IsPinningAllowed` and a
token-less `LimitedAccessFeatures.TryUnlockFeature` call as a
cross-check.

A windowless pre-run probe with `s8pin.exe` on this machine (2026-08-15,
26200.9168) already anchored Q2: `desktopSupport=true` (marker present),
`lafRegKeyPresent=true` with the seed value **absent** (query `0x2`) ⇒
`lafTokenRequired=false`, and `TryUnlockFeature` without a token returned
**`AvailableWithoutToken`** — three independent signals agreeing with the
post-KB servicing level. One flag for the run: windowless, non-foreground
`IsPinningAllowed` read **false**; the docs define it as "whether a pin
request would currently be allowed", so the run re-reads it once the host
window holds the foreground (`isPinningAllowedForeground`) to learn
whether it is a transient-foreground signal or a hard block.

- **Q1 — does the API work from our unpackaged exe, and can it target our
  generated Start entries?** Route A on the article's AUMID (the direct
  answer); route B on our AUMID (acquisition dead end?) and on a packaged
  control (does the call itself work from an unpackaged caller?); route C
  failure stages.
- **Q2 — is the LAF/servicing state runtime-detectable per §8.1, and what
  does each state yield?** Marker interface, `IsPinningAllowed`, registry
  probe, `TryUnlockFeature` status — all recorded and checked for
  consistency with the machine's servicing level. This machine
  (26200.9168 > .7705) exhibits only the **post-KB** state; the pre-KB
  token-required state is covered by Microsoft's documented probe
  semantics, not by measurement (scope bound, §2).
- **Q3 — if a pin lands, is it equivalent to a gesture pin?** Verified
  with BOTH prior oracles: the S-4 pin-folder signal (pinned copy in
  `User Pinned\TaskBar`, AUMID retained in the copy's property store) and
  the S-9 UIA oracle (`AutomationId == "Appid: <AUMID>"`, class
  `Taskbar.TaskListButtonAutomationPeer`, control type Button). Plus:
  click-launch behaves per S-3 (target opens as its own button, pin
  element unchanged — the F-2 invariant), repeat request returns `true`
  with no dialog, and S-4's `RemoveFromList` unpins the API-created pin
  (gesture-free lifecycle closes).

## 2. Accepted outcome

The spike closes when Q1–Q3 have recorded answers and **one of these
decisions is explicit** (all three are accepted outcomes — the plan
assumed the manual gesture all along):

- **Replace** — route A works reliably for our generated entries, the
  consent UX is acceptable (dialog names/icons our launcher, one dialog
  per launcher), and equivalence (Q3) holds: architecture §5's flow
  upgrades — the pin guide drives the API request and the manual gesture
  becomes the fallback for deny/unsupported states.
- **Layer** — the API works but with caveats (e.g. flaky foreground
  handling, unclear dialog identity, servicing-dependent availability):
  the pin guide *attempts* the API first and falls back to the guided
  gesture, keyed off the Q2 runtime detection.
- **Keep manual** — the API cannot target our entries (or is unreliable):
  the gesture stays the baseline; the reasons and a revisit trigger are
  recorded here, and §8.1's row is amended accordingly.

Also required to close: architecture §8.1's S-8 rows confirmed or amended;
feasibility §3 item 2's "open evaluation" resolved; the TODO S-8 item
checked off. Scope bounds: the pre-KB (token-required) state is not
measurable on this machine — the runtime probe is adopted on Microsoft's
documented semantics, and the residual risk (probe wrong on some pre-KB
build) is accepted because the manual gesture remains a full fallback
regardless. Policy-disabled pinning (`IsPinningAllowed == false`) is
likewise designed for (fall back to gesture guidance or surface the
policy), not exercised.

## 3. Environment

- Machine: physical, Windows 11 Pro 26200.9168 (25H2 — same image as the
  S-4..S-7/S-9 runs), it-IT · Date: 2026-08-15 · Artifacts: repo working
  tree.
- Servicing: UBR 9168 ≥ 7705 ⇒ KB5074105 LAF-removal **present**
  (expectation confirmed by every probe, §6.1).
- Baseline: 5 pre-existing pins; preflight hygiene sweep found **no**
  `PinnedLauncher.*` leftovers; gate G0 PASS.
- AppsFolder indexing: the article's AUMID was already indexed at 0.0 s
  (the entry was generated during spike prep, hours earlier — no
  fresh-entry lag datum from this run).

## 4. Test articles

| Piece | Role |
|---|---|
| `bin\s8pin.exe` | C++/WinRT host (unpackaged, WINDOWS subsystem — the request needs a real foreground window): sets the **process-explicit AUMID first**, then runs one route per invocation — `probe` (marker interface, `IsSupported`, `IsPinningAllowed`, LAF registry probe, `TryUnlockFeature`, `IsCurrentAppPinnedAsync`), `pin-current`, `pin-entry`, `pin-tile` — emitting parseable `s8 key="value"` facts (authoritative copy written UTF-8 to a per-run file) |
| Proxy shortcut | `S8 pin test.lnk` → `charmap.exe`, display name *S8 pin test*, AUMID `PinnedLauncher.Test.S8PinApi1` (reserved test namespace, S-9 hygiene), installed in the Start-menu spike folder. Gate **G0**: independent AUMID read-back + binaries present |
| Control AUMID | First of Calculator / Notepad / Settings indexed in `shell:AppsFolder` — packaged entry for route B's control leg; its consent dialog is answered **No** |
| Reused tools | `s9uia.exe` (S-9's UIA oracle walker) for the Q3 equivalence checks; `s4unpin.exe` (S-4's `RemoveFromList`) for hygiene sweep and teardown |

## 5. Protocol

**Execution: run `.\Invoke-S8Protocol.ps1`** — a guided runner in the
S-4..S-9 mold; the human steps are answering the consent dialogs and a few
visual confirmations. Every measurement and answer lands in
`results\s8-run-<timestamp>.json` for transcription into §6.

### 5.1 Hygiene sweep, article

1. Preflight sweep (S-9's failed-run-recovery implementation): enumerate
   the pin folder, unpin `PinnedLauncher.*` leftovers programmatically.
2. Generate the article (gate G0); record build/servicing expectation.

### 5.2 Q2 — windowless probes

3. Auto: `s8pin probe` — desktop-support marker, `IsSupported`,
   `IsPinningAllowed`, LAF registry probe, token-less `TryUnlockFeature`
   status, `IsCurrentAppPinnedAsync`. Auto-check: probe verdict consistent
   with the servicing level (UBR ≥ 7705 ⇒ no token required).

### 5.3 Q1 route A — current-app request, then Q3 equivalence

4. Auto: poll `shell:AppsFolder` for the AUMID (S-6/S-9 indexing lag),
   then `s8pin pin-current` — host window takes foreground,
   `RequestPinCurrentAppAsync` fires. Human: answer the consent dialog
   **Yes**; report the dialog's name and icon.
5. If a pin landed — auto equivalence: S-4 signal (pinned copy appears,
   AUMID read back from the copy), S-9 oracle (`Appid:` AutomationId,
   element shape vs the S-9 baseline). Human: one button visible.
6. Click equivalence: human clicks the pin once; auto detects charmap,
   compares the pin element against its baseline while the target runs
   (F-2), closes charmap gracefully. Human: separate button seen.
7. Auto: repeat `pin-current` — expect immediate `true`; human confirms no
   second dialog.
8. Auto teardown: `s4unpin` on the Start source; pin-folder disappear +
   UIA count 0 (the S-4 lifecycle closes over an API-created pin).

### 5.4 Q1 route B — AppListEntry

9. Auto: `s8pin pin-entry` on our AUMID — records the acquisition chain
   (`AppInfo.GetFromAppUserModelId` → `Package` → entries) and where it
   dead-ends.
10. Auto: `s8pin pin-entry` on the packaged control AUMID. Human: answer
    the control's consent dialog **No** (reaching the dialog is the
    datum); confirm whether it appeared.

### 5.5 Q1 route C — secondary tile

11. Auto: `s8pin pin-tile` — construct/configure/request/status/unpin
    attempts, each stage's HRESULT recorded.

### 5.6 Close-out (when the spike is closed)

12. `Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\PinnedLauncher S8 Spike" -Recurse -Force`
    and `Remove-Item .\out -Recurse -Force`.

## 6. Results

Transcribed from `results\s8-run-20260815-225511.json`; §6.4 from the two
recheck fact files (`s8pin-recheck-run1.txt` / `-run2.txt`, same folder).

### 6.1 Q2 — support + LAF/servicing probes (windowless)

| Probe | Value |
|---|---|
| `ITaskbarManagerDesktopAppSupportStatics` marker | **present** — desktop-app support available |
| `GetDefault()` / `IsSupported` | ok / `true` |
| `IsPinningAllowed` | **`false` windowless — `true` once the host window held the foreground** (§6.2): it is a transient would-a-request-succeed signal, not a policy verdict; the product must read it from a foreground context |
| LAF registry probe | key present, seed value **absent** (query `0x2`) ⇒ `lafTokenRequired=false` |
| `TryUnlockFeature` (no token) | **`AvailableWithoutToken`** |
| Consistency with servicing (UBR 9168 ≥ 7705) | ✅ all three signals agree with the post-KB state |

Only the post-KB state was observable on this machine; the pre-KB
(token-required) state rests on Microsoft's documented probe semantics
(scope bound, §2).

### 6.2 Q1 — the three routes from the unpackaged caller

**Route A — `RequestPinCurrentAppAsync` under the article's AUMID: WORKS.**

| Check | Result |
|---|---|
| Host window foreground | reached at 0 ms (launched from the foreground console) |
| `IsPinningAllowed` from foreground | `true` |
| Consent dialog | ✅ appeared, named **"S8 pin test"** and showed the target's (charmap's) icon — the launcher identity, exactly what the pin-guide UX needs |
| `IsCurrentAppPinnedAsync` before → request → after | `false` → **`true`** → `true` |

**Route B — `RequestPinAppListEntryAsync`: DEAD for us, twice over.**

| Leg | Result |
|---|---|
| Our unpackaged AUMID | `AppInfo.GetFromAppUserModelId` → **`0x80070490`** *element not found* — no `AppListEntry` acquisition path exists for `.lnk`-based entries (matches the SDK finding: only `Package.GetAppListEntries[Async]` produce one) |
| Packaged control (Calculator) | acquisition chain fully works (`AppInfo` → `Package` → 1 entry → acquired; foreground ok) but the request itself fails with **`0x8000000E` "Caller must have package identity"** — no dialog. The API is closed to unpackaged **callers**, regardless of target |

**Route C — secondary tiles: DEAD for us.** `SecondaryTile`
construct/configure succeed, but `RequestPinSecondaryTileAsync`,
`IsSecondaryTilePinnedAsync`, and `TryUnpinSecondaryTileAsync` each fail
with **`0x8000000E` "Caller must have package identity"**.

### 6.3 Q3 — equivalence of the API pin with a gesture pin

| Check | Result |
|---|---|
| S-4 pin-folder signal | ✅ pinned copy present at 0.0 s, AUMID **retained** in the copy (`PinnedLauncher.Test.S8PinApi1`) |
| S-9 UIA oracle | ✅ element identical in shape to the S-9 gesture-pin baseline: `AutomationId="Appid: PinnedLauncher.Test.S8PinApi1"`, class `Taskbar.TaskListButtonAutomationPeer`, control type 50000 (Button), state `0x100000`, name with the localized *bloccato* suffix |
| Visual | exactly one button ✅ |
| Click launch | charmap launched; the pin element was unchanged at the UIA sample instant, but visually the running charmap **merged into the pin** — the article is a *direct-target* `.lnk` (flavor A), so this is S-3's known path-association merge, a property of the article's construction, **not** of how the pin was created; the product's proxy exe (flavor B, distinct AUMID) is the design's answer to exactly this |
| Teardown | ✅ S-4 `RemoveFromList` (S_FALSE) unpinned the API-created pin: copy gone at 0.0 s, UIA element gone — the gesture-free lifecycle closes over an API pin |

### 6.4 Post-run recheck — repeat request and foreground rights

Two extra `pin-current` runs, driven from a **background** console this
time, to pin down the ambiguous repeat-dialog observation:

- **Repeat request is not dialog-free.** Run 2 started with
  `IsCurrentAppPinnedAsync=true` and returned `true` — but the **full
  consent dialog appeared again** (human-confirmed). The documented
  "already pinned ⇒ immediate true, no dialog" behavior was **not
  observed** on 26200.9168. Consequence: the product gates every request
  on `IsCurrentAppPinnedAsync` and never relies on documented idempotency.
- **Foreground rights are real.** Launched from a background process, the
  host could not take the foreground by itself: its taskbar button
  **blinked until clicked** (foreground reached after 8.6 s, vs 0 ms when
  launched from the foreground console). The request must originate from a
  foreground interaction that can pass activation rights to the helper.

## 7. Outcome — recorded 2026-08-15

- **Q1 — yes, via route A only.** From our unpackaged exe,
  `RequestPinCurrentAppAsync` pins a generated Start entry when the
  process assumes that entry's explicit AUMID: one consent dialog carrying
  the launcher's name and icon. Routes B and C are closed:
  `0x8000000E` *caller must have package identity* (and route B
  additionally has no `AppListEntry` acquisition path for unpackaged
  entries — `0x80070490`). Architecture §9's "RequestPinAppListEntryAsync,
  secondary-tile pin/update/unpin" clauses are answered in the negative;
  the current-app route replaces them as the API of record.
- **Q2 — fully runtime-detectable.** Three independent, agreeing signals
  on the post-KB state: the desktop-support marker, the documented
  registry probe (seed absent ⇒ no token), and token-less
  `TryUnlockFeature` (`AvailableWithoutToken`). `IsPinningAllowed` is
  foreground-sensitive and must be read from a foreground context. The
  pre-KB token-required state is adopted on documented probe semantics
  (untestable here); acceptable because the gesture fallback exists on
  every path.
- **Q3 — equivalent.** The API pin satisfies both prior oracles (S-4 copy
  + AUMID retention; S-9 `Appid:` element, same shape), and S-4's
  `RemoveFromList` unpins it — pin *and* unpin are now gesture-free-capable.
  The click-test merge is the article's flavor-A construction (S-3), not
  an API artifact.
- **Decision: LAYER, with the mode user-configurable.** Default flow: the
  pin guide *attempts* route A — a short-lived helper assumes the
  launcher's AUMID and requests the pin, launched from a **foreground**
  interaction of the management window, **gated on
  `IsCurrentAppPinnedAsync`** (§6.4), and only when the Q2 runtime
  detection says the request can succeed — falling back to the guided
  gesture on unavailable/denied. A **pin-flow setting** exposes all three
  §2 postures (*API-first* default / *API-only* / *manual*), inaugurating
  a project rule: **wherever Windows offers alternative mechanisms, the
  choice is a runtime setting**, so behavior can be re-tuned if Windows
  changes without waiting for a release.
- Caveats on record for P1: gate on `IsCurrentAppPinnedAsync` (repeat
  dialog, §6.4); launch the helper with foreground-activation rights;
  read `IsPinningAllowed` from the foreground; re-run the Q2 probes per
  build family alongside the S-3/S-9 confirmation runs.
- Design docs updated (2026-08-15): architecture §5 + §8/§8.1,
  feasibility §3, use-cases UC-1a, management-window §5.3,
  implementation-plan 0.3.0 row, ADR-0006 amendment, TODO.md S-8 item,
  agent-guide status paragraphs.
