# Config schema — design

- Date: 2026-08-16
- Status: **accepted 2026-08-16** (P1 deliverable 1, [implementation-plan §P1](../implementation-plan.md#p1--detailed-design); review outcome recorded in §9; amended after external review, §9 note)
- Normative inputs: [requirements](../requirements.md) NF-12, NF-8, NF-9;
  [architecture §4](../architecture.md#4-shared-core) and
  [§4.3](../architecture.md#43-lifecycle-state-machine) (lifecycle: **normative**);
  [management-window](../management-window.md) §5.2 (capability matrix), §5.3
  (pin-flow modes), §5.4 (settings); [UC-5, UC-6, UC-8, UC-13](../use-cases.md);
  [release-plan](../release-plan.md) §1–§2; spikes
  [S-5](../spikes/s5-editprop.md) (icon path stability),
  [S-8](../spikes/s8-pinapi.md) (pin-flow posture)
- Companion designs: `aumid-scheme.md` (slug + AUMID generation, P1 deliverable 2),
  `cli.md` (who reads config when, deliverable 3), `modules.md` (the store's Q-6
  interface, deliverable 4)

## 1. Principles

- **Single source of truth** (architecture §4): the config file fully determines
  every launcher; icons, proxy shortcuts and jump lists are derived, regenerable
  artifacts. Everything needed to regenerate them lives here, including the custom
  display name.
- **Human-readable, diff-friendly JSON, documented in-repo** (NF-12): this document
  *is* the schema definition. No machine-readable JSON-Schema artifact is shipped:
  there is no native validator to consume it, and the parser's validation code is
  the enforcement (Q-3). Serialization is deterministic (§2), so two configs
  differing in one field differ in one line.
- **Single writer**: only the management app writes the file (it is single-instance
  by mutex, management-window §2). The proxy, in both its launch verb and
  `--request-pin`, only ever reads, and only after the ADR-0011 elevation-type
  guard has passed (placement: `cli.md`). Single-writer holds **across
  sessions**: the manager owns a user-ACLed `Global\` writer lock for its
  lifetime, so a second interactive session of the same user (C-2 includes
  multi-session editions) cannot become a second writer (cli.md §2.1).
- **`schemaVersion` from day one** (release-plan §2): the format is versioned from
  0.1.0; the migration machinery of §8 applies from the first schema change.
- **KISS** (Q-3): no indirection for future needs. Portable mode (NF-13) is
  post-1.0; nothing here precludes it (the file's location is resolved in exactly
  one place), but no location-redirection mechanism is designed now.

## 2. Location, encoding, serialization

| Item | Value |
|---|---|
| File | `%LOCALAPPDATA%\PinnedLauncher\config.json` |
| Siblings | `bin\` (stable install location, release-plan §1), `icons\` (generated `.ico` artifacts, §6) |
| Crash-safety backup | `config.json.bak`: the previous version, produced by every successful write (§7) |
| Migration snapshots | `config.backup-v<N>.json`: the file as it last was at schema version `N`, written before migrating away from `N` (§8) |
| Encoding | UTF-8, no BOM, `LF` newlines, trailing newline |
| Layout | 2-space indent; object keys in the fixed order given by the field tables below, followed by any preserved unknown keys (§7.2) in the order encountered; **valid** `launchers` entries sorted by `slug` (ordinal ascending), flagged entries (§7.2) after them in encountered order |
| Optionals | omitted when unset, never written as `null` |

Deterministic layout is what makes the file diff-friendly (NF-12) and makes
migrator tests byte-comparable (§8). Settings are always written out in full
(self-documenting); launcher optionals are omitted at their defaults.

## 3. Top-level structure

```json
{
  "schemaVersion": 1,
  "settings": {
    "pinFlowMode": "api-first",
    "badgeDefault": true,
    "badgeCorner": "bottom-left"
  },
  "launchers": [
    {
      "slug": "calculator",
      "displayName": "Calculator",
      "target": { "kind": "packaged", "aumid": "Microsoft.WindowsCalculator_8wekyb3d8bbwe!App" },
      "aumid": "PinnedLauncher.Proxy.calculator",
      "proxyLnkPath": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\PinnedLauncher\\Calculator.lnk",
      "state": "awaiting-pin"
    },
    {
      "slug": "notepad",
      "displayName": "Notepad",
      "target": { "kind": "exe", "path": "C:\\Windows\\notepad.exe" },
      "arguments": "D:\\notes\\scratch.txt",
      "workingDirectory": "D:\\notes",
      "windowState": "maximized",
      "aumid": "PinnedLauncher.Proxy.notepad",
      "proxyLnkPath": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\PinnedLauncher\\Notepad.lnk",
      "state": "active"
    },
    {
      "slug": "old-tool",
      "displayName": "Old Tool",
      "target": { "kind": "exe", "path": "D:\\Tools\\oldtool.exe" },
      "aumid": "PinnedLauncher.Proxy.old-tool",
      "proxyLnkPath": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\PinnedLauncher\\Old Tool.lnk",
      "state": "pending-removal",
      "removalOrigin": "active",
      "removalKind": "normal"
    }
  ]
}
```

| Key | Type | Rules |
|---|---|---|
| `schemaVersion` | integer ≥ 1 | required; `1` at 0.1.0; bumped only by a release that ships the matching migrator (§8) |
| `settings` | object | required; §4 |
| `launchers` | array | required (may be empty); §5 |

`schemaVersion` versions the **file format only**. It is independent of the
manager↔proxy binary version handshake (release-plan §1), which guards
mixed-binary operation; §8 defines how each binary treats a file version it does
not know.

## 4. `settings`

Exactly the surface management-window §5.4 defines; nothing speculative. Keys in
this order:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `pinFlowMode` | `"api-first"` \| `"api-only"` \| `"manual"` | `"api-first"` | Pin-flow posture (S-8 decision). The mode × outcome semantics in management-window §5.3 are normative: this field only persists the choice |
| `badgeDefault` | bool | `true` | Default launcher-badge visibility for launchers that don't override it (F-4) |
| `badgeCorner` | `"top-left"` \| `"top-right"` \| `"bottom-left"` \| `"bottom-right"` | `"bottom-left"` | Badge corner, global (F-4, shortcut-arrow spirit; the per-launcher override is visibility only, per the §5.2 dialog) |
| `language` | BCP-47 string, optional | absent = follow Windows | UI language override (NF-11; at least `en`, `it`, `hu`) |

Not settings, by explicit prior decision: AUMID scheme (fixed, UC-10), theme
(system-owned, §5.4), launch behavior (focus-or-launch is post-1.0, TODO),
tray/autostart (post-1.0). Config location is where the file *is*, not a field in
it.

**Badge changes are soft** (maintainer-delegated decision, 2026-08-16 review):
changing `badgeDefault`, `badgeCorner`, or a per-launcher `badge` regenerates
the affected icons **in place** (stable paths, §6) with **no lifecycle
transition**; live pins pick up the new pixels at the next Explorer session
(the S-5 healing behavior). The re-pin flow is reserved for changes to the
display name or the icon **source**. Consequently badge differences never
gate the UC-8 import promotion (§5.3).

## 5. Launcher entries

Keys in this order (fixed serialization order, §2):

| Key | Type | Presence | Meaning |
|---|---|---|---|
| `slug` | string | required | Stable identity: config key, CLI argument (`--edit <slug>`, architecture §4.1), AUMID suffix, icon-artifact filename (§6). **Immutable after creation**: display renames never touch it, and that immunity is what makes AUMIDs rename-stable. Generation, character set, uniqueness and collision handling: `aumid-scheme.md` |
| `displayName` | string, non-empty | required | Pin label and Start-entry name (F-4, UC-5). Uniqueness is *not* required at config level; artifact-filename disambiguation on collision is `aumid-scheme.md`'s concern; UI collision handling is the presenter's (management-window §4) |
| `target` | object | required | §5.1 |
| `arguments` | string | optional | Command-line tail (exe) / activation arguments (packaged); capability matrix in §5.2 |
| `workingDirectory` | string | optional | Working directory (exe only) |
| `elevate` | bool | optional, default `false` | UC-5 "run as administrator". Consumed by the proxy as `runas` **on the resolved target**, never on itself (UC-6 normative, ADR-0011) |
| `windowState` | `"normal"` \| `"minimized"` \| `"maximized"` | optional; absent = inherit a `.lnk` target's own show state (§5.1), `"normal"` otherwise | UC-5 run-minimized/maximized. Absence is semantically distinct from an explicit `"normal"`, which overrides a `.lnk`'s stored show state; the model preserves the distinction |
| `iconOverride` | string (path) | optional | User-chosen icon source (UC-5); absent = extract from the target. Extraction rules: icon service (`modules.md`) |
| `badge` | bool | optional | Per-launcher badge visibility override; absent = inherit `settings.badgeDefault` |
| `aumid` | string | required | The **generated** proxy AUMID as stamped on the `.lnk` (`PinnedLauncher.Proxy.<slug>` under the current scheme). Stored, not re-derived: existing pins and jump lists key on the stamped value, which must survive any future scheme evolution (release-plan §1 alpha-breaking-change rules apply). Duplicate `aumid` values across entries are an entry-scoped validation error (§7.2) |
| `proxyLnkPath` | string (path) | required | The proxy `.lnk` as actually placed in the per-user Start-menu Programs folder (architecture §4). Stored because the filename derives from `displayName` with possible disambiguation: reconciliation must find the real artifact, not a guess. **Confinement rule**: the resolved path must lie inside the per-user `Programs\PinnedLauncher\` Start-menu folder and be unique case-insensitively across entries; anything else is an entry-scoped validation error (§7.2), and artifact operations never write or delete at an unvalidated path — this is what keeps a Full-token manager (cli.md §5) from being steered outside its own directories by a tampered config |
| `state` | one of six strings, §5.3 | required | Persisted lifecycle state (architecture §4.3, normative) |
| `removalOrigin` | `"awaiting-pin"` \| `"active"` \| `"awaiting-repin"` | iff `state` ∈ {`pending-removal`, `removing`} | The state held when removal was requested; consumed by *Cancel removal* (§4.3) |
| `removalKind` | `"normal"` \| `"uninstall"` | iff `state` ∈ {`pending-removal`, `removing`} | Which completion the resumed removal runs (UC-3 delete vs UC-13 tombstone); written atomically with the removal transition (§4.3) |

Path-valued fields (`target.path`, `workingDirectory`, `iconOverride`,
`proxyLnkPath`) are stored as picked/generated; Windows environment variables
(`%APPDATA%`-style) are permitted and expanded at point of use (the
management-window §5.1 mock already displays such a path). Generated artifacts'
paths always use the stable install location contract (release-plan §1).

### 5.1 `target`

| Key | Type | Presence | Meaning |
|---|---|---|---|
| `kind` | `"exe"` \| `"packaged"` \| `"document"` \| `"folder"` \| `"url"` | required | Classification persisted at add/edit time. A `.lnk` is classified by its **resolved destination** (management-window §5.2); for file-system kinds it is stored verbatim as picked (resolution happens at classification and launch; the user's chosen path is not rewritten), while a `.lnk` resolving to a **packaged app or URL** stores the resolved identity (`aumid`/`url`) instead, since those kinds carry no `path` |
| `path` | string | iff `kind` ∈ {`exe`, `document`, `folder`} | File-system target as picked (may be a `.lnk`) |
| `aumid` | string | iff `kind` = `"packaged"` | The **target's** AUMID, for `IApplicationActivationManager` activation (distinct from the launcher's own generated `aumid`) |
| `url` | string | iff `kind` = `"url"` | Absolute URL |

`kind` values map 1:1 onto the capability-matrix columns. F-6 (exe incl.
`.lnk`→exe) is Must scope; the other kinds are F-7 (Should, land 0.7.x). The
schema carries them from day one, so no schema bump is needed when they arrive.

**`.lnk` launch merging** (exe kind): when the entry sets any of `arguments`,
`workingDirectory`, or `windowState`, the launch service resolves the shortcut
(`IShellLink::Resolve` with `SLR_NO_UI | SLR_NOSEARCH | SLR_NOTRACK |
SLR_NOUPDATE` and the minimum timeout: no shell UI, no volume search, no
distributed tracking, inside the NF-3 budget; a failed resolve is a launch
error, never a hang) and merges settings deterministically: the shortcut's
embedded arguments come first with config `arguments` appended; a set config
`workingDirectory` or `windowState` overrides the shortcut's own values, and
unset config fields inherit them. When the entry sets none of them, the proxy
passes the `.lnk` straight to `ShellExecuteEx` and no resolve happens at all.

### 5.2 Per-kind field applicability

Management-window §5.2's capability matrix is normative; the schema enforces it
as **validation, not silence** ("hidden ≠ silently ignored"): a known field
outside its kind's applicability is a validation error on the entry, never
quietly dropped.

| Field | `exe` | `packaged` | `document` | `folder` | `url` |
|---|---|---|---|---|---|
| `arguments` | ✅ | ✅ (activation args) | ❌ | ❌ | ❌ |
| `workingDirectory` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `elevate` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `windowState` | ✅ | ❌ | ✅ best-effort | ✅ best-effort | ❌ |

(`iconOverride` and `badge` apply to every kind.)

### 5.3 Lifecycle fields

The state machine itself (meanings, transitions, reconciliation, cancel
semantics) is architecture §4.3 and is **not restated here**. The schema's
concerns are representation and write discipline:

- `state` values, verbatim: `"awaiting-pin"`, `"active"`, `"awaiting-repin"`,
  `"pending-removal"`, `"removing"`, `"removed"`.
- **Field-presence invariant:** `removalOrigin` and `removalKind` are present in
  exactly the two removal-in-progress states and absent otherwise, including
  `removed`: a tombstone's kind is by definition `uninstall` (UC-3/UC-13), and its
  origin has no remaining consumer (no cancel from a tombstone, §4.3). They are
  written in the same atomic commit that enters `pending-removal`/`removing` and
  dropped in the same atomic commit that leaves them.
- **Every state transition is one atomic file replace** (§7), committed at the
  §4.3-mandated point in its operation: a create's commit is last in the pipeline
  and carries `awaiting-pin`; a visual edit's commit carries `awaiting-repin`; the
  `awaiting-repin` → `awaiting-pin` unpin-observation transition persists
  atomically with the observation; `removing` commits **before** the irreversible
  unpin. The store therefore exposes an atomic read-modify-write of a single
  entry (interface: `modules.md`); there is no multi-file or partial-write state.
- A `removed` tombstone keeps its full entry unchanged apart from `state` (its
  artifacts are already gone); the whole file is deleted as the very last act of
  uninstall, after the user's end-of-summary confirmation (UC-13).
- **Import never trusts identity or lifecycle fields** (UC-8, §4.3): on apply,
  `aumid` and `proxyLnkPath` are regenerated and validated **locally** (never
  adopted from the imported file), imported entries are normalized to
  `awaiting-pin`, and `removalOrigin`/`removalKind` are discarded.
  **Merge-mode precedence** (clarifying the §4.3 wording): merge **adds new
  entries only and never overwrites an existing one**, so existing entries keep
  their state; the `awaiting-repin` rule for an overlapping entry whose
  pin-visible fields change (display name or icon source; badge is soft, §4)
  applies to **replace mode only**. The promotion comparison is honest about
  what is observable: config-level fields plus the pinned copy's **display
  name** (`IPinService::ReadPinnedCopy`); pixel-level equality of the rendered
  icon is **not claimed**, because S-5 makes the pin's displayed pixels
  unobservable and the icon path is invariant by design (§6). Import/export
  scope is the whole file (export = copy, UC-8), settings included; the UC-8
  preview covers the launcher-visible consequences.

## 6. Icon artifacts — the S-5 path-stability rule

Generated icons are **derived, not stored**: each launcher's badged multi-size
`.ico` lives at `icons\<slug>.ico` under the app directory (§2). Because the slug
is immutable (§5), the path is **stable across every regeneration by
construction**, satisfying S-5's rule: the pinned copy references this path
forever; an in-place rewrite leaves an existing pin at worst stale until the next
Explorer session, while a renamed file would break the pin's icon permanently
([S-5 §7](../spikes/s5-editprop.md#7-outcome--recorded-2026-08-15), architecture §4.2). Regeneration always
rewrites in place; no versioned filenames, ever. Not storing the path also keeps
it out of migration's blast radius: one field fewer to ever migrate.

## 7. Atomicity, durability, backup

**Write protocol** (every write, including state transitions):

1. Serialize the full document per §2 into `config.json.tmp` in the same
   directory.
2. `FlushFileBuffers` on the temp handle, then **close it** (`ReplaceFile`
   opens the replacement with no sharing).
3. `ReplaceFile(config.json, config.json.tmp, config.json.bak, …)`: an atomic
   swap that simultaneously retains the previous version as the backup.
   First-ever write (no existing file): `MoveFileEx(MOVEFILE_REPLACE_EXISTING |
   MOVEFILE_WRITE_THROUGH)`.

Consequences:

- **Readers never see a partial file.** The proxy opens with full sharing
  (including `FILE_SHARE_DELETE`, so a concurrent swap is not blocked; detail in
  `modules.md`) and reads a complete old or complete new document. A launch that
  raced an edit and used the old content is correct: the click predates the
  edit's completion.
- **A crash at any point leaves either the old file, or the new file plus a
  `.bak`, or the documented interrupted-replace residue.** `ReplaceFile` has a
  documented partial-failure class (`ERROR_UNABLE_TO_MOVE_REPLACEMENT_2`) that
  can leave no `config.json` while the old content sits in `config.json.bak`
  and the new in `config.json.tmp`; §7.1 treats that residue as an interrupted
  replace, never as a first run. Combined with the §5.3 transition ordering,
  reconciliation always finds a state it can act on (architecture §4.3), never
  a torn document.
- **`config.json.bak` is a one-generation crash net,** not an undo feature (Q-3).
  It is offered for restore only on load failure (§7.1).

Perf note (NF-3): the proxy parses the whole file per click; at the file's
realistic size (tens of entries, single-digit KB) that is microsecond-class. No
cache, no binary sidecar (Q-3; the same "no caching layer warranted" conclusion
as the AppsFolder enumeration check).

### 7.1 Failure handling on load

Scoped so damage is contained and never silently amplified (NF-8 spirit:
diagnose, surface, guided repair):

| Failure | Manager behavior | Proxy behavior |
|---|---|---|
| File missing, no `.bak`/`.tmp` residue | First-run: start with an empty document (written on first change) | Brief native message (no config = no launchers), pointing at the manager (architecture §5's unknown-slug safety net) |
| File missing, `.bak` or `.tmp` present | **Interrupted replace** (§7): offer recovery (restore `.bak`, or adopt a `.tmp` that parses and validates); never a silent first run | Brief native message pointing at the manager; never launches from residue |
| Parse failure / invalid `schemaVersion` (file-level) | Offer restore from `config.json.bak` or start fresh; **never auto-overwrites the broken file**: it is preserved (renamed `config.json.corrupt-<date>`) for inspection | Brief native message; never launches from a file it cannot parse |
| `schemaVersion` newer than the binary knows | Refuse to load, read-only message pointing at upgrading the app (mirror of the release-plan §1 mixed-version refusal); no write occurs | Same refusal, brief native message |
| Entry-level validation error (§7.2) | That entry is flagged broken in the list (NF-8 guided repair); the rest of the config operates normally | Refuses to launch that slug with the brief native message; other slugs unaffected |

### 7.2 Validation policy

Lenient toward the unknown, strict about the known, scoped per launcher:

- **Unknown keys are ignored and preserved.** An unrecognized key at any level
  (top level, `settings`, a launcher entry, `target`) is not an error: the loader
  skips it, and every rewrite carries it through with **value and member order
  preserved**, serialized after the object's known keys in the order
  encountered (§2). Preservation is semantic, not byte-level: canonical
  serialization may normalize whitespace, escape spelling, and number spelling.
  This keeps hand edits and external annotations safe (NF-12 invites both). No misspelling detection is
  attempted: a misspelled optional key simply leaves the intended option at its
  default, and a misspelled *required* key is caught by the next rule, because
  the required key is then missing.
- **Entry-scoped errors**: missing required key, malformed value,
  capability-matrix violation (§5.2), lifecycle field-presence violation (§5.3),
  duplicate slug (all entries involved are flagged). The failure is contained to
  that launcher: it is flagged broken in the manager (NF-8 guided repair) and
  refused by the proxy with the brief native message (§7.1); every other launcher
  in the file keeps working.
- **File-scoped errors**: malformed JSON, or a missing/malformed required
  top-level key (`schemaVersion`, `settings`, `launchers`); handled per §7.1. A
  malformed known *settings* value degrades softly instead: the built-in default
  is used and the problem is flagged; it never blocks the file.
- The manager **does not rewrite the file while file-scoped errors stand**, and a
  rewrite triggered by editing a healthy entry carries flagged entries through as
  parsed (value-and-order preservation, as above): repair changes an entry only
  when the user acts on it (NF-8), never as a side effect of saving something
  else.
- **Flagged entries stay addressable**: they keep their original relative order
  after the sorted valid block (§2) and are addressed **by array position** for
  repair, so an entry with a missing or duplicate `slug` is still individually
  selectable in the manager; hand-editing the file remains the fallback repair
  path NF-12 embraces.
- Validation of paths' existence is **not** a schema concern: a target that is
  currently missing is a reconciliation finding (flagged, repairable), not a
  config error. The file may legitimately describe a temporarily absent target
  (an unplugged drive), and import validates paths as part of its preview (UC-8)
  rather than at parse time.

## 8. Migration design

**Versioned migrators, chained** (release-plan §2: `schemaVersion` from day one,
best-effort in alphas, guaranteed from 0.8.0):

- The binary carries `kCurrentSchemaVersion` and an ordered, contiguous table of
  migrators, one per version step: `migrate_1_to_2`, `migrate_2_to_3`, …. Each is
  a **pure function on the parsed JSON document** (no I/O, no OS calls, no access
  to anything but its input), which is what makes them trivially and exhaustively
  unit-testable. Preserved unknown keys (§7.2) pass through a migrator untouched
  unless its version step explicitly targets them.
- **Load algorithm** (manager): parse → read `schemaVersion` →
  - `== kCurrent`: validate (§7.2), done;
  - `< kCurrent`: write the migration snapshot `config.backup-v<N>.json` (kept
    indefinitely: it is tiny, and it is the user's escape hatch for a
    release-notes-declared alpha breaking change or a bad migrator), run the
    migrator chain in memory, validate the result, write it back through the §7
    protocol, done;
  - `> kCurrent`: refuse (§7.1);
  - `< kCurrent` with **no registered migrator for a step** (a
    release-notes-declared alpha break, release-plan §1): refuse exactly like
    `> kCurrent`, with the message pointing at that release's documented
    repair steps; never guess across a declared break.
- **The proxy never migrates** (single-writer rule, §1): on `< kCurrent` it loads
  through the same in-memory chain without writing back, so launches keep working
  between the upgrade and the manager's first run; on `> kCurrent` it refuses
  (§7.1).
- **Release discipline:** a release that changes the schema bumps
  `kCurrentSchemaVersion` by exactly one and ships the matching migrator in the
  same release. From 0.8.0 this is unconditional (release-plan §2); during alphas
  a release *may* instead declare a breaking change in its release notes with
  documented repair steps (release-plan §1), and the snapshot above is what makes
  those steps safe. Migration machinery + UTs land at 0.7.x (implementation-plan
  §P3) and are green at the 0.8 gate (release-plan §5 step 5).

**Migrator tests** (ADR-0008 `[ut]` tier, tagged `NF-12`):

- Per migrator: fixture pairs (input document at version N, expected document at
  N+1), compared **byte-for-byte after canonical §2 serialization**, covering the
  populated case, the empty case, every optional-field presence variant the step
  touches, and preserved unknown keys.
- Chain test: a representative v1 fixture migrated to `kCurrent` validates
  cleanly under §7.2.
- Doc-drift guard: the §3 example of this document is itself a fixture that must
  parse and validate at `kCurrent`, so the doc cannot silently diverge from the
  code.
- Refusal tests: `schemaVersion` newer / missing / non-integer produce the §7.1
  behaviors, with no write.

## 9. Decisions recorded by this document

Local choices not directly derivable from the cited authorities, surfaced per
the P1 ground rule and **reviewed 2026-08-16**: items 1–3 and 5–8 accepted as
proposed; item 4 decided by the maintainer against the draft's original strict
proposal. None changes an architectural boundary, adds a dependency, or
constrains a future decision an accepted ADR covers, so none became ADR
material:

1. **File placement and names**: `config.json` at the app root beside `bin\` and
   `icons\`; `config.json.bak`; `config.backup-v<N>.json`;
   `config.json.corrupt-<date>` (§2, §7). Follows release-plan §1's directory and
   NF-9's `%LOCALAPPDATA%`, but the exact names are new.
2. **Deterministic serialization discipline**: fixed key order, slug-sorted
   array, omit-unset-optionals, always-explicit settings (§2). NF-12 asks for
   diff-friendly; the specific discipline is chosen here.
3. **`ReplaceFile`-based write protocol with an always-on one-generation `.bak`**
   (§7). "Atomic" is mandated (architecture §4.3); the mechanism and the backup
   policy are chosen here.
4. **Lenient, scoped validation** (maintainer decision, 2026-08-16): unknown
   keys are ignored and preserved through rewrites at every level, with no
   misspelling heuristics; known-key violations are contained to the launcher
   entry they occur in; only structural file-level damage refuses the file
   (§7.2).
5. **Paths stored as picked, environment variables expanded at use; `.lnk`
   targets stored verbatim with their resolved classification persisted in
   `target.kind`** (§5, §5.1). The §5.1 mock and the §5.2 classification rule
   imply but do not state this.
6. **Per-launcher `badge` as an optional bool inheriting the global default**
   (§5): the minimal encoding of "global default + per-launcher toggle"
   (F-4 + §5.2 dialog).
7. **Import applies the whole file (settings included), normalizing lifecycle
   fields** (§5.3). UC-8 specifies launcher preview and state normalization;
   settings scope is chosen here.
8. **Newer-`schemaVersion` refusal in both binaries; proxy migrates in memory
   only, never writes** (§8): extends the release-plan §1 mixed-version refusal
   idea to the file format.

**Amended after external review (Codex, 2026-08-16):** AUMID uniqueness and
`proxyLnkPath` confinement (§5, §7.2); the cross-session writer lock noted in
§1; temp-handle close and interrupted-replace recovery (§7, §7.1); semantic
rather than byte-level preservation wording, and flagged-entry addressing
(§2, §7.2); `.lnk`-to-packaged/URL representation and `.lnk` launch merging
(§5.1); merge-mode precedence, local identity regeneration on import (§5.3);
the soft badge-change rule (§4); missing-migrator refusal across a declared
alpha break (§8). **Second round (same date):** `windowState` absence made
semantically distinct from explicit `"normal"` (§5); bounded no-UI `.lnk`
resolution with a no-override fast path (§5.1); the promotion comparison's
observability stated honestly (§5.3); case-insensitive `proxyLnkPath`
uniqueness (§5).
