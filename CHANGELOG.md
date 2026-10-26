# Changelog

## 0.2.0

- `OpenUI.Runtime.new/2` takes `queries: :on_statement` to run each query as soon as its statement is complete, instead of when the stream ends; the LiveView renderer exposes it as the `queries` attribute. The default is unchanged.
- The LiveView renderer takes a `host` map that every catalog component receives as `@host`.
- `host` is now a reserved assign name: a catalog prop named `host` does not compile with `OpenUI.LiveView.Components`.

## 0.1.1

Fixes found while bringing the line coverage of `lib/` to 100%.

- The LiveView renderer keeps a null in its place in a list prop, so table columns stay aligned.
- `@Each` over a query or mutation named like its loop variable renders the items, as the official renderer does.
- A call nested in a `$variable` default is evaluated, so the state the host receives is plain JSON.
- A DSL `function` without `returns:` compiles, and a slot that takes a single action is written as the official library writes it.
- `Library.from_spec` returns `{:error, problems}` for a LibrarySpec with sections of the wrong type, and `mix openui.gen.spec --check` reports one instead of crashing.
- `OpenUI.Prompt` accepts tool schemas given as plain maps.
- `OpenUI.Serializer` and `OpenUI.Canonical` handle a component that `@Set` stores.

## 0.1.0

First release. Implements OpenUI Lang 1.0 (spec commit `9d73d17`).

- Catalog DSL (`use OpenUI.Library`) that generates the official LibrarySpec, and `mix openui.gen.spec` with backward compatibility checks.
- System prompt byte-identical to `@openuidev/lang-core` 1.0.1.
- Parser, chunked stream, edit merge and serializer; every case of the 1.0 conformance suite passes.
- Runtime for state, forms, validation, actions, `Query` and `Mutation`, as a pure value with effects.
- Stored message protocol (`OpenUI.Message`).
- Optional Phoenix LiveView renderer with per-component crash protection.
- Eight guides, a LiveView chat example and a React example whose contract test compares this library with the official parser.
