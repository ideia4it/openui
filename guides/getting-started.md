# Getting started

This guide goes from an empty Phoenix app to a model answer drawn in LiveView.

## 1. Define a catalog

The catalog lists what a model may use. Positional order matters: it is the order the model writes arguments in.

```elixir
defmodule MyApp.Library do
  use OpenUI.Library, id: "support", version: "1.0.0", root: "Stack"

  component "Stack",
    description: "Lays out children in a column",
    props: [children: [type: {:array, :component}, required: true]]

  component "Metric",
    description: "A labeled number",
    props: [label: [type: :string, required: true], value: [type: :number, required: true]]

  component "Button",
    description: "A clickable button",
    props: [label: [type: :string, required: true], action: [type: :action]]
end
```

The module does not compile if the catalog breaks a rule of the specification, such as a required prop after an optional one.

## 2. Draw the components

```elixir
defmodule MyAppWeb.SupportUI do
  use OpenUI.LiveView.Components, library: MyApp.Library

  def stack(assigns), do: ~H|<div class="flex flex-col gap-2">{@children}</div>|

  def metric(assigns) do
    ~H"""
    <div class="metric"><span>{@label}</span><strong>{@value}</strong></div>
    """
  end

  def button(assigns) do
    ~H"""
    <button {@action || []}>{@label}</button>
    """
  end
end
```

`@children` arrives already rendered. `@action` arrives as the attributes the button needs, or `nil`.

## 3. Teach the model

```elixir
system_prompt = OpenUI.Prompt.generate(MyApp.Library)
```

Send it as the system prompt. The model answers in OpenUI Lang:

```
root = Stack([open, ask])
open = Metric("Open tickets", 12)
ask = Button("Show the oldest", @ToAssistant("Show the oldest open tickets"))
```

## 4. Render the answer

```heex
<OpenUI.LiveView.renderer
  id="answer"
  response={@answer}
  components={MyAppWeb.SupportUI}
  streaming={@streaming?}
/>
```

While the answer streams, pass the text received so far with `streaming={true}`; set it to `false` when the stream ends.

A click on the button sends your LiveView `{:openui, "answer", %OpenUI.Event{human_friendly_message: "Show the oldest open tickets"}}`. Turn it into the next user message.

## Without LiveView

The parser, stream and runtime work on their own:

```elixir
program = OpenUI.Parser.parse(answer, MyApp.Library)
OpenUI.Canonical.result(program, MyApp.Library)["root"]
```

`OpenUI.Runtime` holds state and runs actions as a pure value, for any host.
