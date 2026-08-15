# AGENTS.md

Guidance for AI agents other than Claude Code (e.g. Codex) in this repo.
**Such agents are used for review only.** Working instructions for the
maintainer's Claude Code sessions live in `CLAUDE.md`, not here.

## Your role: read-only reviewer

- **Do not modify, create, or delete any file.** Do not stage, commit,
  push, or run any other git write operation. All edits are reserved to
  the maintainer's own sessions.
- Your deliverable is **findings**: defects, inconsistencies, and risks,
  each with a file/line reference and, where applicable, the requirement
  ID (`F-n`, `NF-n`, `Q-n`, `C-n`) or ADR it violates.

## What you are reviewing

**PinnedLauncher** — a native Windows 11 quick-launch replacement built on
**real taskbar pins**: each launcher is a proxy `.lnk` carrying the
target's icon/name and a distinct AppUserModelID, so clicking launches the
target while the running app opens as its own separate button (the pin
never expands in place). License: GPL-3.0. The project is currently
**docs-as-code** (phase P0 — design and spike evidence; no product code
yet); review the documents as the product.

## Authorities to review against

- [docs/README.md](docs/README.md) — map of all documents.
- [docs/requirements.md](docs/requirements.md) — requirement IDs are
  **stable**; any renumbering is a defect.
- [docs/use-cases.md](docs/use-cases.md) — UC-6 is **normative** for click
  and elevation semantics; contradictions elsewhere are defects.
- [docs/architecture.md](docs/architecture.md) — the design; §8.1 API
  floors; §9 spike definitions.
- [docs/adr/](docs/adr/) — accepted ADRs are **immutable** except dated
  `Amended:` header annotations (rule in ADR-0001); a doc change that
  contradicts an accepted ADR without a superseding ADR is a defect.
- [docs/spikes/](docs/spikes/) — measured evidence backing the design;
  [TODO.md](TODO.md) — work items.

## Hard invariants (violations are always findings)

- **No code injection** into `explorer.exe` or any process; no window
  reparenting into the taskbar; no overlay/flyout/appbar UI on or near the
  taskbar (ADR-0003, ADR-0005, ADR-0006). Documented shell APIs only.
- **No .NET, no WinUI, no bundled runtimes** (NF-1, ADR-0004): modern C++
  (C++20+), Win32 + COM, at most two executables.
- **Confused-deputy guard**: the proxy never executes config-derived
  commands while elevated; elevation applies to the resolved target via
  `runas` (UC-6).
- **Config is the single source of truth**; icons/shortcuts/jump lists are
  derived, regenerable artifacts with persisted lifecycle states
  (architecture §4).
- **KISS** (Q-3): flag speculative abstractions; inheritance where natural,
  no dogma either way (Q-2, ADR-0007).

## Review conventions

- English throughout; one concern per document, cross-referenced rather
  than duplicated (ADR-0002) — flag duplication and broken links.
- Check that spike outcomes are folded consistently into every dependent
  doc (architecture, feasibility, use-cases, management-window, TODO,
  `CLAUDE.md` status paragraph) — stale cross-references are exactly the
  kind of defect this repo cares about.
- When code exists (P1+): Catch2 v3 + trompeloeil, test tags carry
  requirement IDs and tiers `[ut]`/`[qt]`/`[interactive]` (ADR-0008/0009);
  the `verify` script is the quality gate — there is no CI.
