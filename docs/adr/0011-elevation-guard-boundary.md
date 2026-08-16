# ADR-0011 — Elevation-boundary confused-deputy guard and supported environments

- Status: accepted
- Amended: 2026-08-16 — the pre-beta enforcement promised under *Verification
  status* is realized as an explicit release-plan §3 carve-out: the
  environment-profile QTs must be **green with zero skips at the 0.8 gate**
  (maintainer decision: hold beta until they pass), with ADR-0009's skip rule
  annotated accordingly — not via the traceability-mapping check alone.
- Date: 2026-08-16
- Related: [ADR-0006](0006-native-taskbar-pins.md) — the proxy mechanism the guard
  protects; [use-cases.md UC-6](../use-cases.md) — normative click/elevation
  semantics; spike [S-6](../spikes/s6-elevation.md) — verification evidence and the
  predicate this ADR adopts

## Context

The windowless proxy is a trusted generic executable whose behavior is entirely
determined by a **user-writable config file**. UAC's trust statement is the consent
prompt: it names the program being granted the elevated token. If the proxy itself
runs elevated and then executes config-derived commands, any medium-integrity
process could rewrite the config between click and consent and run attacker-chosen
code under a prompt naming our trusted proxy — a classic **confused deputy**, and
effectively a UAC bypass. The shell natively offers vectors that elevate the proxy
(Ctrl+Shift+click on the pin; the jump list's own *Run as administrator* on the
entry name; the programmatic `runas` verb), so the case cannot be designed away.

Spike S-6 (2026-08-15) verified the design's answer on a UAC-enabled system: the
proxy applies elevation to the *resolved target* via `runas` (one prompt, naming
the target), and every elevated-start vector was detected and refused before any
config read. But the design texts stated the guard **absolutely** ("the proxy never
executes config-derived commands while elevated"), while S-6's recommended P1
predicate — *refuse iff the token's elevation type is `TokenElevationTypeFull`* —
is deliberately narrower: in sessions where **UAC is disabled**, or under the
**built-in Administrator** account without Admin Approval Mode, every process runs
at high IL with elevation type `Default`, so the predicate never fires and the
proxy would consume config while technically elevated. The absolute wording and the
predicate cannot both be implemented, and the project wants to **support** those
environments rather than refuse to run there.

## Decision

The guard is defined by **elevation boundary**, not by elevation state:

- The proxy **never executes config-derived commands across an elevation
  boundary**. Predicate: refuse to consume config **iff the process token's
  elevation type is `TokenElevationTypeFull`** — i.e. the proxy was granted a full
  token through a UAC elevation it should not have received. The refusal happens
  before any config read and points the user at the supported per-launcher
  elevation (UC-6).
- **UAC-off and built-in-Administrator sessions are supported.** There the token's
  elevation type is `Default` even at high IL, and the guard deliberately never
  fires: per-launcher elevated launch simply runs (promptless, as the session
  implies), and the refusal message never appears.
- The normative texts (UC-6, architecture §4, the CLAUDE.md hard invariant) carry
  the boundary wording; the previous absolute phrasing is retired.

**Threat-model justification.** The confused-deputy attack requires (a) a consent
prompt to launder — absent in no-boundary sessions, where elevation is silent and
universal — and (b) an attacker *below* the boundary who gains privilege through
the proxy — also absent, since any code able to write the user's config in such a
session already runs with full administrative rights (low-IL/AppContainer code
cannot write medium-labeled user files). The guard therefore protects exactly the
sessions where a boundary exists, and costs nothing where none does. The predicate
reads the token, not machine policy, so it self-adjusts in both directions: if UAC
is enabled later (or the built-in Administrator gains Admin Approval Mode), tokens
split, elevated starts report `Full` again, and the guard resumes firing.

**Verification status.** UAC-enabled behavior is verified (S-6: all three
elevated-start vectors refused before config read; one prompt naming the target).
The no-boundary environments are **reasoned, not yet measured** — S-6 lists them as
an untested residual. Their qualification tests run on a dedicated
UAC-off/built-in-Administrator environment profile (P2 matrix, an environment
dimension orthogonal to the build families) and land **at 0.7.x** with the rest of
elevation hardening; the 0.8 beta gate's full-traceability check enforces that they
exist and pass before beta.

## Consequences

- **Positive:** UAC-off and built-in-Administrator machines are first-class
  supported environments at zero security cost to UAC-enabled machines — on those,
  the boundary guard fires in exactly the same cases as the absolute rule (every
  elevated start in S-6's matrix carried type `Full`). The self-adjusting predicate
  needs no setting, no policy probe, and no migration.
- **Cost:** the support claim for no-boundary sessions rests on token-semantics
  reasoning until the 0.7.x QTs run. Accepted for the alpha train; the beta gate
  closes it.
- **Risk:** the predicate is a single point of security enforcement. Its QTs must
  cover both directions — guard fires on every elevated-start vector under UAC, and
  never fires (while elevated launch still works) in the no-boundary profile.
