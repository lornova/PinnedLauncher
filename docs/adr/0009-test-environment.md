# ADR-0009 — Test environment: Catch2 v3 + CTest, VS 2026 coverage, semi-automated QT harness

- Status: accepted
- Date: 2026-08-13
- Completes: [ADR-0008](0008-test-strategy-ut-coverage-qt.md) (which deferred tool selection)

## Context

ADR-0008 fixed the strategy (full UT + coverage, requirement-traceable QTs, manual
protocol where the shell demands user gestures) and deferred tooling. The development
machine runs Visual Studio 2026 (18.9). Investigation findings (Aug 2026):

- **Catch2 v3** is actively maintained and the developer already knows it.
- **OpenCppCoverage** — the historical default for free C++ coverage on Windows — was
  **archived/retired in July 2026**; no further compatibility updates.
- **Visual Studio 2026 includes code coverage in all editions** (Community,
  Professional, Enterprise; pre-2026 it was Enterprise-only), for native C++, with
  static/dynamic instrumentation, `Microsoft.CodeCoverage.Console` CLI, Cobertura
  export, and native exclusion macros (`ExcludeFromCodeCoverage` /
  `ExcludeSourceFromCodeCoverage`).
- A user-gesture step (pinning) does not force a fully manual test: the gesture can be
  prompted by the harness and everything after it verified programmatically.

## Decision

**Framework: Catch2 v3 + trompeloeil** (one framework for UT and QT), consumed via
CMake `FetchContent` (or vcpkg), built with the same statically linked CRT as the
product (ADR-0004). A framework *is* warranted: assertions, filtering, tags, reporters
and CTest discovery are exactly the infrastructure we must not hand-roll (Q-3).

Mocking: **hand-written fakes remain the default** for state-based tests of the Q-6
seams; **[trompeloeil](https://github.com/rollbear/trompeloeil)** (header-only, active,
ships a Catch2 integration adapter, already known to the developer) is adopted for the
seams where *interaction* verification is what the test asserts — e.g. "`BeginList` →
`AddUserTasks` → `CommitList` called in order with these tasks", "`SHChangeNotify`
fired after the source shortcut was rewritten", "`ShellExecuteEx` received verb `runas`".
Its RAII-scoped expectations (`REQUIRE_CALL` blocks) compose naturally with Catch2
`SECTION`s, which gMock's per-test expectation model does not.

GoogleTest/gMock was considered and rejected — knowingly against raw popularity:
GoogleTest is the most-used C++ test framework industry-wide (JetBrains ecosystem
surveys put it first by roughly 3× over second-place Catch2, and Visual Studio ships a
first-class adapter and project template for it). It would be the default for a team
optimizing for contributor familiarity. Here the calculus differs: the developer has
hands-on experience with *both* Catch2 and trompeloeil; trompeloeil's expectation
syntax is cleaner than gMock's; and Catch2's tag system is load-bearing for this
project's traceability scheme (requirement-ID tags, tier tags, `~[interactive]`
filtering) — GoogleTest has no tags and would emulate them with name-prefix filters.

**Orchestration: CTest** (`catch_discover_tests`), surfaced in Visual Studio 2026's
Test Explorer through the existing CMake integration.

**Coverage: Visual Studio 2026 built-in coverage** (available in every edition).
Test binaries link with `/PROFILE`; CLI runs use
`Microsoft.CodeCoverage.Console instrument/collect`; reports export to Cobertura.
The Q-4 "named, justified exclusions" map directly onto the native
`ExcludeFromCodeCoverage`/`ExcludeSourceFromCodeCoverage` macros, declared in one
dedicated file so every exclusion is visible and reviewable. OpenCppCoverage is
rejected (retired).

**Traceability: Catch2 tags.** Every QT carries its requirement IDs as tags
(`[F-2][NF-9]…`); tier tags separate suites: `[ut]`, `[qt]` (automated, needs a real
shell), `[interactive]` (needs a human gesture). `docs/traceability.md` is generated
by joining test **declarations** (`--list-tests` tags) with execution **results**
(JUnit XML), stamped with product version, **commit SHA, candidate-attempt ID**, OS
build and run date. Release gates consume only results matching the candidate's
version **and** SHA/attempt; restarting a candidate (local tag deleted and recreated
on a fixed commit) begins a new attempt and **invalidates every prior result for that
version**. Matrix machines never need the unpushed tag: they receive the candidate archive —
packaged **once** after local verification, binaries embedding version + SHA and the
archive carrying a candidate manifest (version, commit SHA, attempt ID) — and test it
via the verification script's **artifact mode** (no rebuild), so every matrix result
covers the exact bytes being shipped.
Default/unattended verification runs filter `~[interactive]` (and `~[qt]` where no
interactive desktop session exists).

**Semi-automated QT harness** (replaces most of ADR-0008's "manual protocol"): the QT
executable is a normal Catch2 binary; `[interactive]` tests prompt the operator with a
native **`TaskDialogIndirect`** dialog carrying numbered instructions (e.g. *"Start →
right-click 'Notepad (Launcher)' → Pin to taskbar, then press Done"*) and
Done / Skip / Fail buttons. `Skip` records the test as **not run**: a skipped
Must/Should QT leaves the traceability matrix incomplete and therefore **blocks the
0.9/1.0 release gates** (release-plan §3) — it exists for mid-development runs, not
for releases. After the gesture, **verification is code, not eyeballs**:

- **UI Automation** (`IUIAutomation`, native COM): assert the launcher button exists on
  the taskbar; after launching, assert the target appears as a **separate** button and
  the pin is unchanged — F-2, the core invariant, asserted programmatically. The
  reliability of this oracle (distinguishing the persistent pin from a same-named
  running-target button) is itself validated by **spike S-9** before any QT depends on
  it — on every build family of the qualification matrix, and revalidated whenever the
  matrix gains a new family — together with test-environment hygiene (dedicated
  profile/VM, reserved test-AUMID namespace, teardown, failed-run recovery — defined
  in the test plan).
- **File system**: pinned `.lnk` copy present under `User Pinned\TaskBar`; generated
  `.ico`/AUMID properties correct.
- **Process**: target actually running (right exe, right arguments).

Results flow through Catch2's JUnit reporter into the traceability matrix like every
other test. Purely visual judgments that resist automation (badge legibility at 16 px)
remain the only truly manual checklist items. Driving the pin gesture itself through
UIA (scripting the Start menu) was considered and parked: it would test the shell's UI
rather than our product, and Start menu automation is fragile across builds — optional
experiment, never a dependency.

## Consequences

- One framework, three tiers, one reporting pipeline; the "manual protocol" of
  ADR-0008 shrinks to gesture prompts plus a short visual checklist.
- Coverage requires zero third-party tools — removing the risk of depending on the
  now-retired OpenCppCoverage.
- The harness gains two small native helpers (TaskDialog prompt, UIA assertions) —
  thin, product-independent test utilities, well inside the KISS budget (Q-3).
- Interactive QTs require an interactive desktop session on the target Windows builds;
  they are release-gate tests, not part of default verification runs.
