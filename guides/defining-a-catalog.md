# Defining a catalog

A catalog is a module that uses `OpenUI.Library`. It produces the LibrarySpec of prompt.md, section 2, the same document the official TypeScript library produces for the same definitions.

```elixir
defmodule MyApp.Library do
  use OpenUI.Library, id: "support", version: "1.2.0", root: "Stack"

  component "Stack",
    description: "Lays out children in a column or a row",
    props: [
      children: [type: {:array, :component}, required: true],
      direction: [type: {:enum, ["row", "column"]}]
    ]

  component "LineChart",
    description: "Time series, daily or monthly",
    props: [
      labels: [type: {:array, :string}, required: true],
      series: [type: {:array, {:ref, "Series"}}, required: true]
    ]

  component "Series",
    description: "One line of a LineChart",
    props: [name: [type: :string, required: true], values: [type: {:array, :number}, required: true]]

  function "Percent",
    description: "Part over total as a percentage",
    params: [part: [type: :number, required: true], total: [type: :number, required: true]],
    returns: :string,
    impl: &MyApp.Formulas.percent/1

  action "CopyToClipboard",
    description: "Copies text to the clipboard",
    params: [text: [type: :string, required: true]]

  group "Charts", ["LineChart", "Series"], notes: ["Prefer a chart over a table for series."]
end
```

## Prop options

- `type:` (required), see below.
- `required: true` for a prop the model must pass. Optional props come after required ones.
- `default:` fills the prop when the model leaves it out or passes null. A required prop with a default counts as optional for ordering, which is how you add one later without breaking stored programs.

## Types

| Type | Prompt signature | JSON Schema |
| --- | --- | --- |
| `:string`, `:number`, `:boolean`, `:any` | `string`, `number`, `boolean`, `any` | `{"type": ...}`, `{}` for any |
| `{:enum, ["a", "b"]}` | `"a" \| "b"` | `{"type": "string", "enum": [...]}` |
| `{:array, type}` | `T[]` | `{"type": "array", "items": ...}` |
| `{:object, [field: opts]}` | `{field: T, other?: U}` | object with `properties` and `required` |
| `{:ref, "Card"}` | `Card` | `{"$ref": "#/$defs/Card"}` |
| `{:one_of, [type]}` | `A \| B` | `anyOf` |
| `:component` | `any` | `anyOf` of every component of the catalog |
| `:action` | `ActionExpression` | `{"$ref": "#/$defs/ActionExpression"}` |
| `{:actions, ["CopyToClipboard", "OpenUrl"]}` | `@CopyToClipboard \| @OpenUrl` | `anyOf` of the action shapes |
| `{:binding, type}` | `$binding<T>` | the schema of `type` |

A slot that only takes components (`:component`, `{:ref, ...}`, `{:one_of, refs}`) rejects data: a string there is a `type-mismatch` and is left out.

`{:binding, type}` marks a prop a `$variable` can bind to two ways, such as the value of an input.

## Functions and actions

A function runs in the client. `impl` must be a remote capture (`&Mod.fun/1`); it receives one map keyed by the param names and returns a value of the `returns` type. Functions must be pure.

An action runs in the host: the runtime delivers it as an `OpenUI.Event` whose `type` is the action name and whose `params` are the arguments by name.

## Rules checked at compile time

- Names start with an uppercase letter and are unique across components, functions and actions.
- No name may be a reserved one: `Query`, `Mutation`, `Action`, or a built-in such as `Count` or `ToAssistant`.
- Required props come before optional props.
- `root` and every component of a group exist.
- A `{:ref, ...}` points to a component and an `{:actions, ...}` entry to an action.

## The LibrarySpec file

```bash
mix openui.gen.spec MyApp.Library --out assets/library.json
```

Other clients build their library from this file. In CI, run it with `--check`: it writes nothing and fails when the file is out of date, or when the catalog changed in a way that breaks programs stored with the previous version:

- a prop moved or was removed;
- a new required prop has no default.

These are the backward compatibility rules of prompt.md, section 3.2. Add props only at the end.

## Reading a LibrarySpec

A library defined elsewhere (for example in a React app) can be read too:

```elixir
{:ok, library} = OpenUI.Library.from_spec(File.read!("library.json"), functions: %{"Percent" => &MyApp.Formulas.percent/1})
```

Every function in this guide accepts the struct or the module.
