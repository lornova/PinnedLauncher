# Documentation

All project documentation lives here, versioned with the code ("architecture as code").

## Toolchain

Plain **Markdown**, rendered natively by GitHub/Gitea/VS Code — no build step.

- Diagrams: **Mermaid** fenced code blocks (rendered natively by GitHub and VS Code
  with the built-in Markdown preview + Mermaid extension).
- Decisions: **ADRs** in [adr/](adr/), following the
  [MADR](https://adr.github.io/madr/) lightweight template.
- Rationale: this project is small and single-developer. Sphinx/reStructuredText would
  add a build pipeline, a theme, and a toolchain (Python) that the project itself does
  not need. If the docs ever outgrow flat Markdown, MkDocs (Material) can be layered on
  top of these same files without rewriting them — that is the escape hatch, recorded in
  [ADR-0002](adr/0002-markdown-docs-toolchain.md).

## Map

| Document | Question it answers |
|---|---|
| [feasibility.md](feasibility.md) | Can this be built on Windows 11 at all, and how have others done it? |
| [use-cases.md](use-cases.md) | What does the user do with it? |
| [requirements.md](requirements.md) | What must it do, how well, and under which constraints? |
| [architecture.md](architecture.md) | Which designs are viable, and which one do we pick? |
| [management-window.md](management-window.md) | How is the app's only UI structured, and why plain Win32? |
| [ui-reference.md](ui-reference.md) | Which interaction patterns do mature launchers (GNOME/KDE) converge on? |
| [release-plan.md](release-plan.md) | How do 0.x previews progress to a stable 1.0? |
| [implementation-plan.md](implementation-plan.md) | In what order is this built, phase by phase, release by release? |
| [adr/](adr/) | Why did we decide what we decided? |
| [spikes/](spikes/) | What evidence did each P0 spike produce, and what was decided from it? |
| [../TODO.md](../TODO.md) | What must land before 1.0, and what is deferred after? |

## Conventions

- One document per concern; link between documents instead of duplicating content.
- Requirements have stable IDs (`F-n`, `NF-n`, `C-n`) so ADRs, issues, and future code
  comments can reference them.
- ADR decisions are immutable once accepted; superseding decisions get a new ADR that
  links back. Dated `Amended:` header annotations (evidence, status notes, factual
  corrections that leave the decision unchanged) are allowed — see ADR-0001.
