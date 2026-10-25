# OpenUI for Elixir

An unofficial Elixir implementation of OpenUI Lang 1.0, published on Hex as `openui`. The library is generic: no product, company or customer from any user of it appears in code, tests, docs or examples. Examples use a neutral support-ticket domain.

## Source of truth

- The specification is `spec/language.md`, `spec/prompt.md` and `spec/fixtures/1.0/README.md` of https://github.com/thesysdev/openui at commit `9d73d17d2bbac565672a85e78f6eb7740cb0d9ca`.
- The conformance fixtures in `test/fixtures/openui-spec/` are the contract. When the prose and a fixture disagree, the fixture wins; report the disagreement upstream.
- The reference implementation is `@openuidev/lang-core` 1.0.1 (MIT). Each module here ports one or more of its files:

| Elixir module | Reference (`packages/lang-core/src/`) |
| --- | --- |
| `OpenUI.Library` | `library.ts`, `signature.ts`, `functions.ts`, `parser/validate-library.ts` |
| `OpenUI.Parser.Lexer` | `parser/lexer.ts`, `parser/tokens.ts` |
| `OpenUI.Parser.Source`, `OpenUI.Parser.Statements` | `parser/parser.ts` (`stripFences`), `parser/statements.ts` |
| `OpenUI.Parser.Expression` | `parser/expressions.ts`, `parser/ast.ts` |
| `OpenUI.Parser`, `OpenUI.Parser.Materializer`, `OpenUI.Parser.Validator` | `parser/parser.ts`, `parser/materialize.ts`, `parser/validation.ts`, `parser/builtins.ts` |
| `OpenUI.Runtime.*` | `runtime/*.ts`, `utils/validation.ts` |
| `OpenUI.Stream` | `parser/parser.ts` (`createStreamParser`) |
| `OpenUI.Edit` | `parser/merge.ts` |
| `OpenUI.Serializer` | `parser/serialize.ts` |
| `OpenUI.Prompt` | `parser/prompt.ts` |
| `OpenUI.Message` | `message.ts` |

## Commands

```bash
mix deps.get
mix precommit      # compile --warnings-as-errors + format + credo --strict + test
mix dialyzer
```

Update the fixtures only to a new pinned commit: `scripts/sync-fixtures.sh <sha>`.

## Rules

- Zero runtime dependencies. `phoenix_live_view` is optional; code that needs it lives only in `lib/openui/live_view*` and compiles only when it is loaded.
- Nothing a model generates may raise to the host. Public functions that take model text or values return a result; they never raise.
- Comments explain why, never what. Never use the em dash character in our text. The U+2014 separator the prompt requires is written as the escape `—`.
- Moduledocs, guides, README and comments in English. Test names in English, BDD style. Commits are conventional, in English.
- JavaScript tooling runs with `bun`, never `npm`.
- Publishing to Hex happens only on an explicit order from the maintainer.
