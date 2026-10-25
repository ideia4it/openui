# Errors and safeguards

Nothing a model writes may crash the host (language.md, section 10). A mistake removes the smallest unit it touches, everything else renders, and every removal is reported.

## Error codes

| Code | Source | When | What happens |
| --- | --- | --- | --- |
| `unknown-component` | parser | Component not in the catalog | Left out; in a list, the `:unknown` slot shows in its place |
| `missing-required` | parser | A required prop is absent | Its default fills it, or the component is dropped |
| `null-required` | parser | A required prop is null | Same as above |
| `type-mismatch` | parser | A value does not fit the prop's type or enum | The default, or the optional prop or list item is removed; a required prop drops the component |
| `excess-args` | parser | More arguments than props | Extra arguments are dropped |
| `inline-reserved` | parser | `Query` or `Mutation` used inside an expression | That expression is left out |
| `unknown-function` | parser | `@Name` that does not exist | The call is null; the statement stays |
| `no-root` | parser, runtime | No usable entry statement | A warning when a fallback entry renders; nothing renders otherwise |
| `parse-failed` | parser | Text with no statements | Nothing renders |
| `parse-exception` | parser | The parser itself failed | Nothing renders; caught, never raised |
| `runtime-error` | runtime | A function raised or got bad arguments; a component raised while rendering | The value is null; the component is left out |
| `tool-not-found` | query, mutation | The tool does not exist | The query keeps its defaults; the hint lists the tools |
| `tool-error` | query, mutation | The tool failed or raised | The query keeps its last data; a mutation reports the error and stops its action |

## The error object

`OpenUI.Error.to_map/1` gives the wire shape of language.md, section 8.3, ready to send to the model:

```json
{"source": "parser", "code": "missing-required", "statementId": "chart", "component": "Metric",
 "path": "/value", "message": "missing required field \"/value\"", "hint": "Signature: Metric(label*, value*). * marks required"}
```

The renderer reports the list only when it changes, and `[]` once it recovers. While a stream is open nothing is reported: a half-written program is not an error.

## The four protections of the LiveView renderer

1. **Program mistakes** follow the table above.
2. **Unknown components** render the `:unknown` slot, or nothing.
3. **Host components that raise.** Each component renders once inside a rescue. One that raises is left out, reported as `runtime-error` with its statement, and logged with its stacktrace. The rest of the page renders.
4. **Failures of the renderer itself**, such as a broken components module, leave the program empty and are logged. The page stays up.

## Text cut in the middle

A stream can stop anywhere, even inside a multibyte character. The stream holds those bytes until the rest arrives; text that is still cut when parsed shows U+FFFD in place of the stray bytes. Data from tools gets the same treatment.

## Logging

Protections 3 and 4 log with `Logger.error`, including the component and the stacktrace, so a bug in your components shows up in your error tracker while the person sees the rest of the answer.
