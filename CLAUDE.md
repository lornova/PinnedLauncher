# CLAUDE.md

## What this project is

**PinnedLauncher** — a native Windows 11 quick-launch replacement built on **real
taskbar pins**: each launcher is a proxy `.lnk` with the target's icon/name and a
distinct AppUserModelID, so clicking launches the target while the running app opens
as its **own separate button** (the pin never expands in place). License: GPL-3.0.

## Spirit (weigh every process decision against this)

This is **hobby software**, vibe-coded for fun, to create a useful tool *for
the creator*. It is not enterprise software. The SWE apparatus (requirements,
ADRs, spikes, tests) exists to keep order and structure and to make the
implementation easier and less error-prone; it must be **helpful, never a
bureaucratic religion**. Process-as-religion is exactly how enterprise
software derails, and it does not happen here: prefer the lightest artifact
that does the job, keep security to essential best practices for a per-user
desktop tool, and surface only decisions that are genuinely hard to reverse.
None of this licenses sloppiness; it is the yardstick for proportion.

**Current status: design complete, implementation not started** (the only code
is the compiling Q-6 interface skeletons in `src/pl/`). **P0 is complete**
(2026-08-16: S-3 GO recorded 2026-08-15, spikes S-4..S-9 accepted, ADR-0011
elevation-boundary guard, ADR-0012 uniform flavor B, name/license closed).
**P1 is complete (2026-08-16)**: four accepted design docs in
[docs/design/](docs/design/) (config schema, AUMID scheme, CLI + process
contracts, modules), all amended after an external Codex review;
[ADR-0013](docs/adr/0013-product-dependencies-nlohmann-json.md)
(product-dependency policy, nlohmann/json); Q-6 interface headers compile
clean (`src/pl/`, MSVC /W4 /WX). Next: **P2** (test plan + verify script),
**not started** by explicit maintainer instruction. See
[docs/implementation-plan.md](docs/implementation-plan.md) for phases P0–P3 and
the release train.

## Where authority lives

- [docs/README.md](docs/README.md) — map of all documents.
- [docs/requirements.md](docs/requirements.md) — requirement IDs (`F-n`, `NF-n`,
  `Q-n`, `C-n`) are **stable**; reference them, never renumber.
- [docs/use-cases.md](docs/use-cases.md) — UC-6 is the **normative** source for click
  and elevation semantics.
- [docs/architecture.md](docs/architecture.md) — the design; §9 lists spikes S-3..S-9.
- [docs/adr/](docs/adr/) — decisions. Accepted ADRs are immutable; factual annotations
  require a dated `Amended:` header line (rule in ADR-0001). Superseding a decision
  requires a new ADR.
- [TODO.md](TODO.md) — pre-1.0 vs post-1.0 work items.

## Hard invariants (do not violate in any change)

- **No code injection** into `explorer.exe` or any process; no window reparenting into
  the taskbar; no overlay/flyout/appbar UI drawn on or near the taskbar (ADR-0003,
  ADR-0006). Documented shell APIs only.
- **No .NET, no WinUI, no bundled runtimes** (NF-1, ADR-0004): modern C++ (C++20+),
  Win32 + COM, at most two executables (management app + windowless proxy).
- **Confused-deputy guard**: the proxy never executes config-derived commands
  **across an elevation boundary** — refuse iff the token's elevation type is
  `Full` (ADR-0011); elevation applies to the resolved target via `runas` (UC-6).
  UAC-off / built-in-Administrator (without Admin Approval Mode) sessions are
  supported: no boundary exists there and the guard deliberately never fires.
- **Config is the single source of truth**; icons/shortcuts/jump lists are derived,
  regenerable artifacts with persisted lifecycle states (architecture §4).
- **KISS** (Q-3): no speculative abstractions; inheritance where it is the natural
  fit, without dogma either way (Q-2, ADR-0007).

## Conventions

- Docs-as-code: plain Markdown + Mermaid, no build step (ADR-0002). One concern per
  document; link, don't duplicate.
- Tests (when code starts): Catch2 v3 + trompeloeil, tags carry requirement IDs and
  tiers `[ut]`/`[qt]`/`[interactive]` (ADR-0008/0009); coverage via VS 2026 built-in
  tooling. Quality gate = the `verify` script (release-plan §4) — there is **no CI**.
- Single-developer flow: work lands on `master`, one commit per 0.x.y step
  (release-plan §4). **Never stage/commit/push without an explicit instruction**
  (global rule in `~/.claude/CLAUDE.md`).
- English for all docs/code; at least en + it + hu localization planned (NF-11).
- `AGENTS.md` is a **read-only reviewer's guide** for non-Claude agents (the
  maintainer uses e.g. Codex for reviews only). It deliberately does **not**
  mirror this file and carries no status paragraph — never sync content between
  the two; status updates land here only.
