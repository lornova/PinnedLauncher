# ADR-0008 — Test strategy: full unit testing with coverage, requirement-driven QTs

- Status: accepted (strategy level; tool selection deferred to implementation start)
- Date: 2026-08-13
- Implements: requirements Q-4, Q-5, Q-6

## Context

The project owner requires full unit testing with coverage measurement, plus
qualification tests (QTs) that validate the requirements themselves. The product's
riskiest behaviors live at the shell boundary (AUMID grouping, pinned-copy updates,
jump lists), some of which need a real user gesture (pinning) and therefore cannot be
fully automated.

## Decision

**Unit tests (Q-4).**
- Every module ships with unit tests; tests are first-class code in the same repo.
- All OS boundaries are mocked via the Q-6 interfaces, so core logic (config store,
  icon pipeline decisions, AUMID scheme, shortcut property assembly, jump-list content,
  CLI argument handling of the proxy) runs entirely in-process with no live shell.
- Line/branch coverage is measured on every build. Core logic targets full line
  coverage; exclusions are allowed only for pure OS pass-through code and must be
  named and justified where they are declared.

**Qualification tests (Q-5).**
- Each Must/Should requirement (F-n, NF-n) maps to at least one QT carrying that ID.
- The mapping lives in `docs/traceability.md` (created together with the first QTs).
- QTs are automated where Windows allows (e.g. verifying generated `.lnk` properties,
  AUMIDs, icon files, jump-list commits, config round-trips, launch semantics against
  a test target). Behaviors requiring a user gesture or visual confirmation on the
  live taskbar (the one-time pin, never-expand-in-place, badge legibility) get a
  **scripted manual protocol**: numbered steps + expected observations, versioned in
  the repo and executed per release on the supported Windows builds.
- The spike results (the P0 spikes, S-3 .. S-9) graduate into QTs: what was verified
  once by hand becomes a repeatable protocol entry.

**Tooling** — deferred to implementation start, recorded then in a follow-up ADR.
Candidates consistent with the no-.NET constraint: GoogleTest or Catch2 (test
framework), OpenCppCoverage or MSVC instrumentation (coverage), CTest orchestration
under the existing CMake choice (ADR-0004).

## Consequences

- Q-6 seams are non-negotiable from the first commit — retrofitting testability onto
  shell-coupled code is the expensive path this decision avoids.
- The manual protocol is honest about what Windows does not let us automate, instead
  of pretending taskbar UX can be asserted from a unit test.
- Coverage numbers are a tripwire, not a goal: the named-exclusion rule keeps the
  metric meaningful without gaming it on OS glue.
