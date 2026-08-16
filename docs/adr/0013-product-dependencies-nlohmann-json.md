# ADR-0013 — Third-party product dependencies: policy, and nlohmann/json for config JSON

- Status: accepted
- Amended: 2026-08-16 — external review (Codex): (1) the `FetchContent` pin
  must be an **immutable reference** (a full commit hash, or a release archive
  with `URL_HASH`); a tag alone is movable and does not pin the bytes.
  (2) The release archive must carry a third-party-notices file: nlohmann/json
  is MIT with embedded MIT, CC0-1.0 and Apache-2.0 components whose notices
  require retention. Both strengthen the Decision's condition 5 and the
  release packaging expectations (release-plan §5 step 3).
- Amended: 2026-08-16 — second review round: the simdjson rejection rationale
  is factually corrected; current simdjson does provide builder/serialization
  APIs. The operative reason stands unchanged: it offers no mutable
  insertion-ordered DOM, which the config store requires. The table cell below
  stays as recorded; this note governs.
- Date: 2026-08-16
- Related: [ADR-0004](0004-cpp-win32-stack.md) (the stack this extends),
  [ADR-0009](0009-test-environment.md) (third-party *test* dependencies and the
  FetchContent/static-CRT mechanics this reuses); requirements C-1, NF-1, NF-3,
  NF-12, Q-1, Q-3; [config-schema.md](../design/config-schema.md) (the
  requirements the library must meet)

## Context

The config store needs a JSON implementation with a specific shape: DOM-level
parse and write (migrators are document transforms, config-schema §8),
insertion-order preservation (deterministic serialization §2; unknown keys
preserved verbatim through rewrites, §7.2), and UTF-8 correctness. Until now
every third-party library in the project was test-only (Catch2, trompeloeil;
ADR-0009): nothing external ships in the product binaries. C-1 prohibits
third-party **GUI frameworks** specifically, and NF-1 prohibits bundled
runtimes; neither prohibits a statically compiled library. The first dependency
that ships inside the product is a distinct decision class (shipped artifact,
license compatibility, supply chain), so it is recorded as an ADR rather than
resting on ADR-0009's test-scope precedent.

## Decision

**Policy for product-code dependencies.** A third-party library may be used in
product code only when all of the following hold, and each adoption is recorded
in an ADR:

1. Implementing the capability in-house is a correctness liability or
   substantial effort with no differentiating value (Q-3: the abstraction must
   earn its place; so must the dependency).
2. Header-only or statically linked into our binaries; no runtime, no
   redistributable, no DLL (NF-1).
3. License is permissive and GPL-3.0-compatible.
4. Actively maintained.
5. Consumed via CMake `FetchContent` pinned to a tagged release (the ADR-0009
   mechanics), built with the same statically linked CRT as the product
   (ADR-0004).

**nlohmann/json is adopted** (its `ordered_json` type) as the config store's
JSON implementation. Rationale against the alternatives considered:

| Candidate | Verdict |
|---|---|
| **nlohmann/json** | ✅ order-preserving DOM (`ordered_json`) plus writer, exactly the config-schema shape; idiomatic modern C++ API (Q-1 vocabulary); MIT; the most widely deployed C++ JSON library, actively maintained; header-only |
| RapidJSON | ❌ order-preserving and fast, but a C-ish API with manual allocator threading (against the Q-1 idiom), and releases have effectively stalled |
| simdjson | ❌ parser only, no writer |
| Boost.JSON | ❌ capable, but drags the Boost footprint in for no gain |
| Hand-rolled parser | ❌ UTF-8 and number-handling edge cases are a correctness liability with zero payoff at our file sizes |

Raw performance was deliberately **not** a criterion: the proxy parses a
single-digit-KB file once per click, well inside the NF-3 margin
(config-schema §7's perf note).

## Consequences

- **Positive:** correct UTF-8, number, and escaping behavior for free; the
  §7.2 unknown-key preservation and the §8 migrator chain become simple DOM
  code; the dependency policy above gives every future "just add a library"
  impulse a recorded bar to clear.
- **Costs:** moderate compile-time overhead (header-only single include);
  roughly a hundred KB of binary size; a supply-chain surface, mitigated by
  pinning to a release tag under `FetchContent` and reviewing bumps like any
  other change.
- The test-vs-product dependency boundary is now explicit: ADR-0009 governs
  test-only libraries, this ADR governs anything that ships. nlohmann/json is
  the only product dependency; admitting another requires a new ADR under this
  policy.
