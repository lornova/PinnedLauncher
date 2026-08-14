# ADR-0007 — Modern C++ OOP style: inheritance where natural, KISS everywhere

- Status: accepted
- Date: 2026-08-13
- Implements: requirements Q-1, Q-2, Q-3

## Context

The project owner wants modern C++ with an explicitly **object-oriented** design and a
deliberate stance on inheritance: current fashion treats inheritance as something to
avoid reflexively; this project does not. At the same time the codebase is small and
single-purpose, so overdesign is the bigger practical risk.

## Decision

**Style baseline (Q-1).** C++20 minimum; RAII for every resource (`wil`-style or
hand-rolled RAII wrappers for HANDLEs, COM via smart pointers, `unique_ptr` by
default); `std` vocabulary types (`string_view`, `optional`, `expected`, `span`,
`filesystem::path`); no raw owning pointers; warnings-as-errors.

**OOP with unapologetic inheritance (Q-2).** The design is class-based, and
inheritance is used wherever it is the *natural* expression:

- **Polymorphic seams**: abstract interfaces over OS boundaries (shell, file system,
  registry, process launch — required anyway by Q-6) with production and test
  implementations.
- **Is-a hierarchies** where the domain has them, e.g. launcher target kinds
  (`Win32Target`, `PackagedAppTarget`, `DocumentTarget`, `UrlTarget`) sharing a
  `LauncherTarget` base with virtual `Launch()`, `ExtractIcon()`, `Describe()`.
- **Template method** where a workflow skeleton is fixed and steps vary (e.g. proxy
  shortcut creation: common flow, per-target-kind steps).

Rules that keep it sane: public inheritance only for genuine is-a; interfaces have
virtual destructors; concrete classes are `final` unless designed as bases;
`override` everywhere; no multiple inheritance of implementation (multiple *interface*
inheritance is fine, it's the COM model anyway).

**KISS (Q-3).** No speculative abstraction: an interface exists only when there is a
second implementation today (the test double counts) or an OS boundary to isolate. No
DI containers, no factory-of-factories, no event buses, no plugin systems. Prefer a
plain function to a class with one method; prefer a `struct` to a class with getters
that return every member.

## Consequences

- The class model doubles as the testability model: the Q-6 seams are ordinary
  abstract base classes, mocked by hand or with the chosen test framework (ADR-0008).
- Inheritance appearing in review is evaluated on fit, not on fashion; conversely,
  "we might need it later" is not an accepted justification for any abstraction.
- The style is enforceable mechanically where possible (clang-format for layout,
  clang-tidy checks aligned with these rules — tool configuration decided at
  implementation start).
