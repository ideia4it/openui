# OpenUI

An unofficial Elixir implementation of the [OpenUI Lang 1.0 specification](https://github.com/thesysdev/openui/tree/main/spec): the language a model writes to describe a user interface, streamed and rendered as it arrives.

It passes every case of the 1.0 conformance suite (`spec/fixtures/1.0` at commit `9d73d17`) and generates system prompts byte-identical to the official `@openuidev/lang-core` 1.0.1.

## What it does

- **Catalog.** Define your components, functions and actions in Elixir; get the LibrarySpec (`library.json`) other clients, such as a React or React Native app, build their library from.
- **Prompt.** Generate the system prompt that teaches a model your catalog.
- **Parser and stream.** Read a response whole or a chunk at a time. A mistake drops the smallest unit and is reported; nothing a model writes raises.
- **Runtime.** State, forms, validation, actions, `Query` and `Mutation`, as a pure value that returns effects for the host to run.
- **LiveView.** An optional renderer that draws programs with your own function components.

It ships no components. Each host draws its own.

## Installation

```elixir
def deps do
  [
    {:openui, "~> 0.1"},
    # only for the LiveView renderer
    {:phoenix_live_view, "~> 1.1"}
  ]
end
```

## A first program

```elixir
defmodule MyApp.Library do
  use OpenUI.Library, id: "myapp", version: "1.0.0", root: "Stack"

  component "Stack",
    description: "Lays out children in a column",
    props: [children: [type: {:array, :component}, required: true]]

  component "Metric",
    description: "A labeled number",
    props: [label: [type: :string, required: true], value: [type: :number, required: true]]
end

prompt = OpenUI.Prompt.generate(MyApp.Library)

program = OpenUI.Parser.parse(~S"""
root = Stack([open])
open = Metric("Open tickets", 12)
""", MyApp.Library)
```

In LiveView:

```heex
<OpenUI.LiveView.renderer id="answer" response={@answer} components={MyAppWeb.UI} streaming={@streaming?} />
```

## Guides

- [Getting started](guides/getting-started.md)
- [Defining a catalog](guides/defining-a-catalog.md)
- [LiveView](guides/liveview.md)
- [Generating with ReqLLM](guides/req-llm.md)
- [Jido.AI agents and Query](guides/jido-ai.md)
- [A React app on a Phoenix backend](guides/react-app.md)
- [Errors and safeguards](guides/errors-and-safeguards.md)
- [Stored programs](guides/stored-programs.md)

## Examples

- [LiveView chat](https://github.com/ideia4it/openui/tree/main/examples/liveview_chat): a support assistant with ReqLLM or a Jido.AI agent, one `elixir` command each.
- [React app on a Phoenix backend](https://github.com/ideia4it/openui/tree/main/examples/react_app): the official React renderer drawing the same catalog, with a contract test that runs the official parser and this library over the same programs in CI.

## License

MIT, Copyright (c) 2026 Ideia4IT. The conformance fixtures and the fixed text of the prompt come from [OpenUI](https://github.com/thesysdev/openui), MIT, Copyright (c) 2011-2024 Thesys Inc.; see `NOTICE`.
