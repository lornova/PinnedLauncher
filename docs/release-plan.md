# Release plan

- Date: 2026-08-13
- Applies from the first public tag onward.

## 1. Distribution model

Open-source project in a **public GitHub repository**. Every release is a Git tag
`vMAJOR.MINOR.PATCH` with a GitHub Release carrying release notes and a self-contained
binary zip (no installer required — per-user, no admin, NF-4). All pre-1.0 releases
are marked **"Pre-release"** on GitHub.

**Stable-path contract (upgrades).** Pins and generated shortcuts embed the proxy
executable's path, so the executables must live at a **stable per-user location**:
on first run (or when started from elsewhere, e.g. a Downloads folder) the app offers
to install itself to `%LOCALAPPDATA%\PinnedLauncher\bin` and continues from there; every
generated artifact references only that path — never a transient folder. (Stable
installation ships in **0.3.0** with the first proxy; releases 0.1–0.2 have no
installed footprint, so the contract's upgrade checks first apply at 0.4 over 0.3 —
checklist §5 step 4.)

**Upgrade mechanics (staged, not file-by-file over a live directory):** extract to a
sibling `bin.new`; ensure nothing is running (single-instance mutex for the manager;
proxies are millisecond-lived); swap directories (`bin` → `bin.old`, `bin.new` →
`bin`); keep `bin.old` until the next upgrade as rollback. Manager and proxy perform a
**version handshake** and refuse mixed-version operation, so a partially applied
upgrade fails loudly instead of running incoherent binaries. During alphas a release
may declare a **breaking change** (config schema / AUMID scheme / CLI) in its release
notes; in that case documented migration or repair steps (regenerate via the
management window) replace the pins-keep-working expectation. From 0.8 compatibility
is unconditional. The release checklist verifies fresh install and in-place upgrade
(§5 step 4).

Prerequisites for going public (see [TODO.md](../TODO.md)): final project name and an
OSS license — both must be settled **before the first public tag**, since renaming and
relicensing later are disproportionately painful.

## 2. Version scheme and stages

Semantic versioning from 1.0 onward; pre-1.0 the minor number encodes the maturity
stage:

| Versions | Stage | Meaning |
|---|---|---|
| 0.1 – 0.7 | **Alpha** (previews) | Features land continuously. Anything may change: config schema, AUMID scheme, CLI. Config schema carries a `schemaVersion` field from day one, but migration between alphas is best-effort. |
| 0.8.x | **Beta** | **Feature freeze at 0.8.0**: every Must and Should requirement implemented. Only bug fixes and polish. At least one beta is published. Config migrations are guaranteed from 0.8.0 onward. |
| 0.9.x | **Release candidate** | **Bug fixes only** — no polish, no refactoring. At least one RC is published. |
| 1.0.0 | **Stable** | The last RC **promoted**: the **same source commit** re-tagged `v1.0.0` and rebuilt through the full release flow. Zero source changes; the rebuild is verified, not assumed identical (§2.1). |
| 1.x | Stable line | SemVer: PATCH = fixes, MINOR = backward-compatible features (see post-1.0 items in [TODO.md](../TODO.md)). |

### 2.1 Version single-sourcing

The version is **not stored in the source tree**. The release flow passes the version
to the build **explicitly** (the tag name being released → CMake → VERSIONINFO
resource / About text); `git describe` is only the fallback for ad-hoc local builds
(stamped `0.0.0-dev+<short-sha>`). The explicit parameter also removes any ambiguity
when one commit ends up carrying both the RC and the 1.0 tags. Consequences:

- There are no version-bump commits, so `v0.9.n` (last RC) and `v1.0.0` point at the
  **same commit** — the promotion guarantee is *source identity*: same source, same
  toolchain configuration, a fresh full verification run of the promoted artifact.
  **Byte-level reproducibility is not claimed** (timestamps and toolchain details may
  differ between builds); an executable cannot honestly claim 1.0.0 without being
  rebuilt with that stamp, so the rebuild is verified, not assumed.
- The 1.0.0 rebuild runs the same verification script (clean build + full automated
  test tiers, §4) as every release; the RC soak validates the source, the script run
  validates the rebuild.

## 3. Stage gates

| Gate | Entry criteria |
|---|---|
| **0.8.0 (beta / feature freeze)** | All M/S requirements implemented; traceability matrix complete (every M/S requirement → ≥1 QT, Q-5); UT coverage target met (Q-4); user-facing docs (README quick start + screenshots) written; code-signing decision executed (TODO). |
| **0.9.0 (first RC)** | Zero known defects against Must requirements; full QT suite green — automated tiers via the verification script, `[qt]`/`[interactive]` tiers executed on all supported Windows 11 builds (test-plan matrix); **zero skips**: a Must/Should QT recorded as skipped leaves the matrix incomplete and blocks the gate (ADR-0009); localization complete (en, it, hu). |
| **1.0.0** | Last RC has soaked with no new defects found (minimum one week of dogfooding); promotion = re-tag the same commit + a verified same-source rebuild (§2.1). |

## 4. Branching (KISS, single-developer)

Development happens **directly on `master`** — no pull requests (there is no second
reviewer to gate on) and no routine feature branches:

- Work accumulates locally; **one commit lands on `master` per 0.x.y step**, when that
  step is stable locally (builds clean, UTs green). `master` is therefore releasable
  by construction: every commit on it *is* a stable step.
- Release tags are cut from `master`.
- Branches exist only as **exploration tools** — trying an alternative implementation
  or design side by side — and end their life merged or deleted; they are never part
  of the release flow. No develop branch, no gitflow.

**Verification without CI.** There is no CI infrastructure and none is required: the
quality gate is a **one-command local verification script** (`verify` — PowerShell +
CMake presets) that performs a clean configure + build, runs the automated test tiers
(default: UTs; release mode: UTs + `[qt]`), and enforces the coverage threshold. It is
the same gate everywhere it is mentioned in this plan: before each `master` commit
(lightweight mode at the developer's discretion) and mandatorily within each release
flow — where the tag is created locally *first*, so the verified build carries its
version stamp (checklist §5). If
hosted CI is ever wanted (GitHub Actions is free for public repos and needs no
infrastructure of ours), it would simply run this same script — see the optional item
in [TODO.md](../TODO.md).

## 5. Release checklist (every release)

Ordered so that **what ships is what was verified**:

1. Create the release tag **locally** (not pushed).
2. Run the verification script in release mode — it builds stamped from that tag —
   clean build, UTs, coverage threshold, automated QTs. Any failure ⇒ delete the local
   tag, fix, restart; a restart is a **new candidate attempt** and invalidates every
   prior result for that version (ADR-0009).
3. **Package once**, from the step-2 verified build outputs: the zip's binaries embed
   version + commit SHA, and the archive carries a **candidate manifest**
   (version, commit SHA, attempt ID). Every subsequent step tests **this exact
   archive** — nothing is ever rebuilt after this point.
4. Smoke-test the *extracted archive*: (a) fresh install in a clean profile — app
   starts and the deepest flow shipped so far works (0.1–0.2: app starts; from 0.3:
   proxy launches its target; from 0.4: add-launcher reaches the pin guide);
   (b) staged **upgrade** over the previous release (§1 mechanics) — applicable from
   the release *after* stable installation ships (it arrives in 0.3, so the first
   meaningful upgrade check is 0.4 over 0.3); existing pins still launch, or, for a
   release-notes-declared alpha breaking change, the documented migration/repair
   steps work as written.
5. For 0.8+: distribute the step-3 archive to each machine of the build matrix and
   run the verification script in **artifact mode** (`verify --artifact <zip>` —
   automated `[qt]` tier plus the interactive protocol, executed against the packaged
   binaries, **no rebuild**); archive all results (stamped with the manifest's
   version/SHA/attempt). Config-migration UTs green.
6. Release notes: changes, known issues, config schema changes (and migration notes
   from 0.8 onward).
7. Push the tag; publish the GitHub Release (pre-release flag until 1.0); attach the
   **tested** zip + checksums.
