# CLI and process contracts — design

- Date: 2026-08-16
- Status: **accepted 2026-08-16** (P1 deliverable 3, [implementation-plan §P1](../implementation-plan.md#p1--detailed-design); §7 decisions accepted, mutex naming amended to reverse-domain in review; amended after external review, §7 note)
- Normative inputs: [architecture §4.1](../architecture.md#41-per-launcher-right-click-menu-jump-list-tasks)
  (jump-list task commands), [§4](../architecture.md#4-shared-core) (launch
  service), [§5](../architecture.md#5-setup-flow-one-pin-consent-per-launcher--api-first-gesture-fallback-s-8)
  (`--request-pin`); [management-window](../management-window.md) §2 (entry
  points, single instance), §5.3 (pin-flow modes);
  [UC-3, UC-6 (normative), UC-7](../use-cases.md);
  [ADR-0011](../adr/0011-elevation-guard-boundary.md) (guard predicate and
  placement), [ADR-0012](../adr/0012-uniform-flavor-b.md) (two executables);
  [requirements](../requirements.md) NF-1, NF-2, NF-3, NF-4, NF-11;
  [release-plan §1](../release-plan.md#1-distribution-model) (version handshake); spikes
  [S-6](../spikes/s6-elevation.md) (guard vectors, exit-code precedent),
  [S-8](../spikes/s8-pinapi.md) (pin-request caveats)
- Companion designs: [config-schema.md](config-schema.md) (what is read),
  [aumid-scheme.md](aumid-scheme.md) (the slug the CLI addresses), `modules.md`
  (which service implements each verb)

## 1. The two executables

ADR-0012 spends the full NF-1 budget: exactly two binaries, both in the stable
install location `%LOCALAPPDATA%\PinnedLauncher\bin` (release-plan §1).

| Binary | Subsystem | Role |
|---|---|---|
| `PinnedLauncher.exe` | WINDOWS (GUI) | Management app: main window, dialogs, and the slug-addressed verbs below; single-instance; exits when the window closes (management-window §2) |
| `PinnedLauncherProxy.exe` | WINDOWS (windowless) | The per-click proxy (uniform flavor B): launch verb + `--request-pin` verb; never shows a window of its own on the launch path |

Slugs on every command line come from
[aumid-scheme.md §3](aumid-scheme.md#3-slug-generation):
alphabet `a-z0-9-`, so no quoting or encoding issues arise in `.lnk` argument
strings or `WM_COPYDATA` payloads.

## 2. `PinnedLauncher.exe` (manager) verbs

Exactly one verb per invocation; management-window §2's entry-point table is
the behavioral source. Grammar:

```
PinnedLauncher.exe
PinnedLauncher.exe --add
PinnedLauncher.exe --edit <slug>
PinnedLauncher.exe --remove <slug>
PinnedLauncher.exe --open-location <slug>
PinnedLauncher.exe --launch <slug> --elevated
```

| Verb | Behavior |
|---|---|
| *(none)* | Open the main view |
| `--add` | Open the main view on the add flow (UC-1; jump-list task *Add a new launcher…*) |
| `--edit <slug>` | Open directly on that launcher's edit dialog (UC-5; task *Change name or icon…*) |
| `--remove <slug>` | Open the remove confirmation for that launcher (UC-3; task *Remove this launcher*) |
| `--open-location <slug>` | `SHOpenFolderAndSelectItems` on the resolved target: file kinds get their containing folder with the item selected, a folder target opens itself (capability matrix, management-window §5.2). No window is opened beyond Explorer's |
| `--launch <slug> --elevated` | The jump-list *Run as administrator* task (architecture §4.1): the launch service applies the `runas` verb to the **resolved target**, exactly the proxy's elevated path (UC-6 normative; S-6 verified: same mechanism, same process class). `--elevated` is **mandatory**: a plain `--launch` is a usage error (surface trimmed per Q-3 after the 2026-08-16 external review) |

Behavioral rules:

- **Capability gating is at publish time**: `--open-location` and `--launch
  --elevated` are only ever *published* for target kinds that support them
  (architecture §4.1). If invoked anyway (stale jump list, hand-typed), the
  verb validates against the capability matrix and shows a localized error
  dialog instead of acting.
- **Unknown slug**: the slug-addressed verbs open the main view with a notice;
  start-time reconciliation has already flagged whatever inconsistency made the
  slug stale (architecture §4). No silent failure, no crash.
- **Unknown or malformed arguments**: localized error dialog, exit code 2. A
  stale jump list from an older binary is the realistic source; the dialog
  points at re-opening the manager (which re-commits jump lists on
  reconciliation).
- All verbs run at the user's integrity level; nothing here elevates the
  manager itself (NF-4). For `--launch` and `--open-location` the ADR-0011
  guard applies (§5).

### 2.1 Single-instance forwarding

Management-window §2 mandates the mechanism; this is the contract:

1. At start, acquire **two** locks, both named with the fixed reverse-domain
   prefix (uniqueness backed by the maintainer's ownership of `lornova.it`;
   names never change across versions):
   - `Global\it.lornova.PinnedLauncher.ConfigWriter.<user SID>`, a user-ACLed
     cross-session mutex held for the manager's whole lifetime. `Local\` is
     the *session* namespace, and C-2 includes multi-session editions, so
     this is what actually enforces config-schema §1's single-writer
     contract; if another session owns it, show a localized notice and exit.
     The SID suffix (the user's SID string) keeps the `Global\` namespace,
     which is machine-wide, from coupling *different* users' independent
     per-user configs: each user gets their own lock.
   - `Local\it.lornova.PinnedLauncher.Manager`, the per-session
     single-instance mutex driving the forwarding below. First owner proceeds
     as *the* instance and registers its main window under a window class
     name carrying the same prefix, which is what the second instance's
     `FindWindow` keys on.
2. A second instance finds the existing instance's window and forwards its
   **entire command line** via `WM_COPYDATA`, sent with `SendMessageTimeout`
   (10 s): on timeout, delivery failure, or a UIPI drop it shows the localized
   error dialog instead of exiting as if it had succeeded. Payload:
   `dwData = 1` (payload-format version), `lpData` = the sender's product
   version string, then the raw UTF-16 command line, each NUL-terminated.
3. Before sending, the second instance calls
   `AllowSetForegroundWindow` for the first instance's process, so the running
   window may legitimately come to the foreground; the receiver executes the
   forwarded verb exactly as if freshly invoked (management-window §2: "always
   land in one window") and activates itself.
4. Startup race (mutex exists, window not yet registered): the second instance
   waits bounded (2 s, polling), then shows the localized error dialog and
   exits with code 4; the user's next click simply works.

The receiver registers `ChangeWindowMessageFilterEx(hwnd, WM_COPYDATA,
MSGFLT_ALLOW)` at window creation: without it, UIPI silently drops the message
whenever the running instance is elevated (a state §5 permits) and a
normal-integrity jump-list invocation would do nothing. The receiver then
validates the payload (`dwData`, sender product version, well-formed verb) and
ignores anything else: `WM_COPYDATA` is receivable from any same-desktop
process, and an unrecognized payload must not crash or act (the verb surface
is the same as the command line's, so nothing more powerful is exposed; the
filter allowance is safe precisely because validation, not the filter, is the
security boundary). A sender product version differing from the receiver's is
refused with the §6 repair message.

## 3. `PinnedLauncherProxy.exe` verbs

```
PinnedLauncherProxy.exe <slug>
PinnedLauncherProxy.exe --request-pin <slug>
```

### 3.1 Launch verb (the pin's command line)

Every proxy `.lnk` carries `PinnedLauncherProxy.exe <slug>` as its command
line (positional slug, no flag). Sequence, in contract order:

1. **ADR-0011 guard** (§5): evaluated **before the config file is opened**.
   Refusal shows the localized message pointing at the supported per-launcher
   elevation (UC-6) and exits with code 3, touching nothing.
2. **Version coherence** (§6): compare own version with the manager binary's
   VERSIONINFO in the install directory; mismatch refuses with the repair
   message, exit code 7.
3. Read config (read-only; in-memory migration when the file is older,
   refusal when newer — config-schema §8).
4. Resolve the slug. Unknown, `removed`, or entry-flagged slug: brief native
   message offering cleanup by opening the manager (architecture §5's safety
   net; config-schema §7.1), exit code 4.
5. Launch per the entry: `ShellExecuteEx` for file-system kinds (arguments,
   working directory, `windowState` via `SW_*`, `runas` verb iff `elevate`,
   which makes the UAC prompt name the resolved target, UC-6; a `.lnk`-based
   exe target is resolved and merged per config-schema §5.1) **and for URL
   targets** (default verb on the URL string);
   `IApplicationActivationManager::ActivateApplication` (created
   `CLSCTX_LOCAL_SERVER`, architecture §8) for packaged kinds. A declined UAC
   ends silently with `ERROR_CANCELLED` (S-6), exit code 1.
6. Exit immediately (NF-2). NF-3's bound applies to this verb: proxy start to
   the `ShellExecuteEx`/activation call in under 100 ms; the tripwire is
   active from 0.3.0 (implementation-plan) and covers the §6 version check.

### 3.2 `--request-pin <slug>` (the pin-request helper)

The S-8 contract, verbatim from the spike's caveats (architecture §5,
management-window §5.3):

1. **ADR-0011 guard first**, same as the launch verb; a helper spawned by a
   Full-token parent inherits the elevated token and carries the same
   signature (S-6 Q2), so the guard holds even if the manager's own check
   (§5) were bypassed.
2. Read config; resolve the slug; assume the launcher's identity via
   `SetCurrentProcessExplicitAppUserModelID(<aumid>)` **before any window is
   created** (the documented ordering; the stored `aumid` field is
   authoritative, config-schema §5).
3. Create the minimal helper window and take the foreground. The helper must
   be **launched from a foreground interaction** that passes activation
   rights (S-8 §6.4: a background-launched helper only blinks); the manager
   owns that context (the guide button at 0.4, the interactive console at
   0.3).
4. Re-read `IsPinningAllowed` from the foreground (S-8: it is
   foreground-sensitive); gate on `IsCurrentAppPinnedAsync` (S-8 §6.4: the
   consent dialog re-appears on already-pinned requests, contra documented
   idempotency). Already pinned: exit 0 without a request.
5. `RequestPinCurrentAppAsync`; the consent dialog carries the launcher's
   name and icon (S-8). Exit with the outcome code.
6. This verb lives for the duration of the consent dialog: NF-2's
   exits-immediately bound explicitly does not apply to it (architecture §5);
   it still exits the moment the request resolves.

The exit code is an **advisory fast path** for the manager's UX; the
authority on whether a pin landed is the watcher plus the persisted lifecycle
state (management-window §5.3: an API success with an inconclusive watcher
never yields `active`). The windowless runtime probes (desktop-support
marker, LAF registry probe) run in the manager *before* spawning the helper
(architecture §8.1); the helper re-checks only the foreground-sensitive
signal.

### 3.3 Proxy exit codes

Following the S-6 spike's proven shape, shared by both verbs:

| Code | Meaning |
|---|---|
| 0 | Launched / pin request succeeded / already pinned |
| 1 | Cancelled by the user (UAC declined, `ERROR_CANCELLED`; consent dialog denied) |
| 2 | Config unusable (missing, unparseable, or `schemaVersion` newer — config-schema §7.1) |
| 3 | ADR-0011 guard refusal |
| 4 | Unknown, removed, or flagged slug |
| 5 | Operation failed (launch error, pin API error) |
| 6 | Pin request not available (foreground `IsPinningAllowed` false, or API unsupported — `--request-pin` only) |
| 7 | Mixed-version installation detected (§6) |

Codes 1 and 6 let *API-only* mode distinguish "user said no" (re-request only
on explicit *Retry*) from "not possible now" (park with *Retry*), per the
management-window §5.3 table, without parsing any text.

## 4. Messages and localization

Every user-visible string from either binary (guard refusal, unknown-slug
cleanup offer, error dialogs) is a localized resource (NF-11), presented
through native dialogs (`TaskDialogIndirect` where buttons are needed,
`MessageBox` otherwise; S-6 verified a message box displays fine from the
windowless elevated proxy). The proxy's messages are brief and terminal: one
dialog, then exit; recovery actions always route to the manager.

## 5. Confused-deputy guard placement (ADR-0011)

- **Predicate** (both binaries, evaluated once at process start from the
  process token): refuse iff `GetTokenInformation(TokenElevationType)` returns
  `TokenElevationTypeFull`. `Default` (no boundary: UAC off, built-in
  Administrator) and `Limited` (normal session) proceed. Exactly ADR-0011; the
  S-6 matrix separates the cases perfectly. **A failed token query fails
  closed**: it is treated as `Full` and refused, so no error path can bypass
  the guard (the seam returns `Result`, modules.md §6).
- **Proxy**: the check precedes any config read, in both verbs (§3.1 step 1,
  §3.2 step 1). This is the ADR's letter, verified behaviorally by S-6 on all
  three elevated-start vectors.
- **Manager**: the same predicate gates the verbs that *execute config-derived
  commands*: `--launch --elevated` and `--open-location`
  refuse with the same message before acting. The manager itself still opens
  under a Full token: configuration editing crosses no boundary the guard
  protects (the threat is executing config-derived commands under a laundered
  consent, ADR-0011's threat model), and refusing to open would just break an
  elevated-shell user's ability to fix things. S-6 frames `--launch` as the
  proxy's mechanism in the manager's process ("same mechanism, same process
  class"), so the guard travels with it.
- The refusal message is the S-6-verified UX: name what happened (the app was
  started elevated), state that config-driven launches are refused across an
  elevation boundary, point at the per-launcher *Run as administrator*
  property (UC-6). No config content appears in the message.

## 6. Version coherence (release-plan §1 handshake)

Both binaries are stamped from the release tag (release-plan §2.1). The
**first-run bootstrap precedes the handshake**: when started outside the
stable install location, the manager first offers the release-plan §1
install-to-`%LOCALAPPDATA%` copy and re-executes from there; the handshake
below applies to the **installed** pair, so a genuine first run (no installed
proxy yet) is not misread as a mixed-version state. The
"refuse mixed-version operation" contract is realized in two halves:

- **Manager, at every start**: read `PinnedLauncherProxy.exe`'s VERSIONINFO
  from the install location; on mismatch with its own, block with a localized
  repair message (re-extract the release zip / finish the staged swap) before
  any pipeline runs. This is the loud failure release-plan §1 wants after a
  partially applied upgrade.
- **Proxy, at every click**: compare own version with the manager binary's
  VERSIONINFO in the same directory; mismatch refuses with the repair message
  (exit code 7). This makes the release-plan §1 handshake **symmetric**, a
  deliberate strengthening from the 2026-08-16 external review replacing the
  earlier schema-gate-only design: pins invoke the proxy directly and must
  not run a half-swapped installation, and the warm cost of reading one
  version resource sits far inside the NF-3 budget. The config
  `schemaVersion` gate (config-schema §8) remains as the second,
  content-level guard, and the forwarding payload's product-version field
  (§2.1) closes the last gap (a fresh invocation forwarding into an older
  still-running manager).

## 7. Decisions recorded by this document

Local choices not directly derivable from the cited authorities, surfaced per
the P1 ground rule and **accepted 2026-08-16** (item 5's mutex name amended to
the reverse-domain form during review):

1. **Proxy executable name `PinnedLauncherProxy.exe`** (§1). The docs name the
   manager (`PinnedLauncher.exe`, management-window §2 and the §4.1 task
   lines) but never the proxy binary. Alternative rejected: multiplexing both
   roles into one exe (NF-1 would allow it) couples the GUI app's lifetime,
   manifest, and single-instance logic into the click path that NF-3 bounds.
2. **Positional slug as the proxy's launch verb** (§3.1): the pin `.lnk`
   command line is `PinnedLauncherProxy.exe <slug>`. Alternative: a `--launch`
   flag mirroring the manager; rejected as noise in every generated shortcut
   for no disambiguation gain (the proxy has exactly one other verb, which is
   flagged).
3. **Proxy exit-code table** (§3.3), extending the S-6 spike's codes; codes 1
   and 6 are what management-window §5.3's mode table keys on.
4. **Guard scope in the manager** (§5): the ADR-0011 predicate gates
   `--launch` and `--open-location`, while the management UI itself remains
   usable under a Full token. An application of ADR-0011's threat model to the
   second binary, not a new security decision; S-6's "same mechanism, same
   process class" framing already implies it.
5. **Single-instance mechanics** (§2.1): mutex name
   `Local\it.lornova.PinnedLauncher.Manager` (reverse-domain uniqueness,
   maintainer decision: the maintainer owns `lornova.it`), the same prefix in
   the main window's class name for `FindWindow`, versioned UTF-16
   `WM_COPYDATA` payload, `AllowSetForegroundWindow` handoff, bounded
   startup-race wait.
6. **Version-handshake realization** (§6): manager-side binary check at start;
   proxy-side coherence via the config `schemaVersion` gate only, keeping the
   click path unburdened (NF-3).
7. **`--launch` without `--elevated` is valid** (§2): plain launch, published
   nowhere today; keeps the flag orthogonal instead of fusing
   `--launch-elevated` into one token. (A launch affordance in the UI remains
   a non-goal, management-window §1.)

**Amended after external review (Codex, 2026-08-16):** Item 1's claim that no
prior document named the proxy binary was wrong: architecture §3's flavor-B
cell loosely wrote `PinnedLauncher.exe` for the pin target; architecture §3
now carries the corrected name (`PinnedLauncherProxy.exe`). Item 5 gains the
cross-session `Global\` writer lock, the UIPI message-filter allowance,
`SendMessageTimeout` with an explicit failure path, and a product-version
field in the forwarding payload (§2.1: `Local\` is session-scoped, so it
alone could not enforce single-writer on C-2's multi-session editions).
Item 6 is superseded: the version handshake is symmetric, the proxy checks
the manager binary per click (§3.1, §6, exit code 7). Item 7 is withdrawn:
plain `--launch` is a usage error (§2). **Second round (same date):** the
global writer lock is SID-qualified (§2.1: `Global\` is machine-wide, not
per-user); a failed token query fails closed as `Full` (§5); the first-run
install bootstrap explicitly precedes the version handshake (§6).
