# ADR-0012 — Uniform flavor B: every pin targets the windowless proxy

- Status: accepted
- Date: 2026-08-16
- Related: [ADR-0006](0006-native-taskbar-pins.md) — defined the two flavors and
  left the choice open (recommending B); [ADR-0004](0004-cpp-win32-stack.md) — the
  executable budget this decision spends; [ADR-0011](0011-elevation-guard-boundary.md)
  — elevation semantics that only a proxy can implement; spikes
  [S-3](../spikes/s3-aumid.md) and [S-6](../spikes/s6-elevation.md) — the P0.3
  evidence base

## Context

ADR-0006 admits two implementation flavors per launcher: the pin's `.lnk` targets
the app directly (**A**) or a tiny windowless proxy exe (**B**, recommended).
Phase P0.3 closes that choice from S-3 + S-6 evidence.

The evidence, and the analysis on top of it:

- **S-3**: flavor-A pins to **plain Win32 exes merge via target-path association**
  — every instance of the target, however launched, folds into the pin, which is
  the stock behavior this project exists to eliminate. Flavor B passed for all
  three target classes. S-3's own feed to P0.3: B mandatory for plain Win32; A
  "viable but benefit-free" for self-AUMID and packaged targets.
- **Feature dependencies**: everything beyond a bare click — per-launcher args,
  working directory, run-mode, the elevation feature with its confused-deputy
  guard (UC-5/UC-6, ADR-0011), optional focus-or-launch (UC-10) — requires code of
  ours in the click path. Flavor A has none; a flavor-A launcher cannot offer them.
- **The hybrid's hidden cost**: keeping A for "clean" targets requires machinery no
  document specifies — a persisted flavor field, eligibility detection (a target's
  self-AUMID is not externally readable), and an A→B transition (with mandatory
  re-pin, per S-5) whenever a launcher later gains args or elevation. Left
  unspecified, the transition is a silent-breakage bug: the pinned copy keeps
  launching the old direct command.
- **No hedge value** *(reasoned analysis, not measurement)*: under the taskbar
  resolver's documented precedence — explicit window/process AUMID beats
  shortcut/path heuristics — any future platform change that broke B's decoupling
  for self-identifying targets would break A identically, and for heuristic Win32
  targets A is already broken. B's coverage is a strict superset of A's in every
  resolver behavior consistent with the documented model, so retaining A buys no
  resilience. The standing empirical check stays: S-3/S-9 revalidation per C-2
  build family, with per-launcher, cosmetic containment on failure.

## Decision

**Flavor B uniformly: every launcher's pin `.lnk` targets the windowless proxy
exe.** Flavor A is retired — no per-launcher flavor field, no eligibility
detection, no A/B transition logic exists in the design. The proxy is thereby a
**definite** second executable (the "at most two" of NF-1/ADR-0004 is spent:
management app + proxy).

## Consequences

- **Positive:** one click path for every target class — the elevation feature
  (ADR-0011), per-launch options, and focus-or-launch are uniformly implementable;
  the S-3 merge risk is closed by construction for plain Win32; the hybrid's
  specification debt (flavor persistence, eligibility, transitions) is never
  incurred; lifecycle and reconciliation stay single-shaped.
- **Cost:** one windowless process per click, launching the target and exiting —
  bounded by the NF-3 latency and NF-2 exits-immediately tripwires active from
  0.3.0. The proxy exe must exist from release 0.3 (it does: it is the 0.3
  dogfooding deliverable).
- **Risk shift:** unsigned-exe friction (feasibility R-6) can no longer be dodged
  per-launcher by "A where possible" — full weight lands on the code-signing
  decision already deadlined before beta (TODO).
- ADR-0006 is **not superseded**: its decision (AUMID proxy shortcuts as the
  mechanism) stands; this ADR closes the parameter it left open. ADR-0006 and
  ADR-0004 carry dated annotations pointing here.
