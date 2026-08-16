# ADR-0002 — Markdown + Mermaid + ADRs instead of Sphinx/reST

- Status: accepted
- Amended: 2026-08-16 — factual correction: the stable-ID families are `F-n`,
  `NF-n`, `Q-n`, `C-n`; quality goals (`Q-n`) were omitted from the Decision's
  list although requirements.md defines them and later ADRs reference them.
- Date: 2026-08-13

## Context

The author is fluent with Sphinx/reStructuredText, but this is a small, single-developer,
single-product repo. Sphinx brings a Python toolchain, a build step, theming, and CI
overhead. The documentation set is expected to stay small (< ~20 documents).

## Decision

- Plain Markdown files under `docs/`, no build step.
- Mermaid fenced blocks for diagrams (rendered natively by GitHub and VS Code preview).
- MADR-style ADRs under `docs/adr/`.
- Stable requirement IDs (`F-n`, `NF-n`, `C-n`) as the cross-reference mechanism that
  Sphinx roles would otherwise provide.

## Consequences

- Zero-toolchain docs: any editor and any forge render them.
- No semantic cross-referencing or link checking; acceptable at this scale, mitigated by
  the ID convention.
- Escape hatch: MkDocs (Material) can later serve these same files unchanged if a
  published docs site is ever wanted; Sphinx+MyST could too. No rewrite required.
