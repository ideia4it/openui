# Changelog

## 0.1.0

First release. Implements OpenUI Lang 1.0 (spec commit `9d73d17`).

- Catalog DSL (`use OpenUI.Library`) that generates the official LibrarySpec, and `mix openui.gen.spec` with backward compatibility checks.
- System prompt byte-identical to `@openuidev/lang-core` 1.0.1.
- Parser, chunked stream, edit merge and serializer; every case of the 1.0 conformance suite passes.
- Runtime for state, forms, validation, actions, `Query` and `Mutation`, as a pure value with effects.
- Stored message protocol (`OpenUI.Message`).
- Optional Phoenix LiveView renderer with per-component crash protection.
- Eight guides, a LiveView chat example and a React example whose contract test compares this library with the official parser.
