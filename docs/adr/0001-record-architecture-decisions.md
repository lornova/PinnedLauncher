# ADR-0001 — Record architecture decisions

- Status: accepted
- Date: 2026-08-13

## Context

The project starts with a feasibility study and will accumulate decisions whose
rationale is easy to lose (especially platform-constraint workarounds on Windows 11,
where the *why* is more important than the *what*).

## Decision

Record every architecturally significant decision as an ADR in `docs/adr/`, using a
lightweight MADR-style template: Context / Decision / Consequences, numbered
sequentially, immutable once accepted, superseded by new ADRs rather than edited.

Amendment rule: an accepted ADR may receive **annotations** —
verification evidence, status notes, factual corrections — marked with a dated
`Amended:` line in its header, provided the decision itself is unchanged. Changing a
decision always requires a new, superseding ADR. During the docs-only phase (before
implementation starts), editorial revisions are additionally permitted and must be
noted in the header the same way.

## Consequences

- Decisions survive context loss between work sessions.
- Rejected alternatives stay documented (crucial here: several taskbar techniques are
  rejected for non-obvious reasons like update fragility, not because they don't work).
