# Jido.AI agents and Query

A [Jido.AI](https://hex.pm/packages/jido_ai) ReAct agent calls tools to answer a question. With OpenUI it still does: the model calls a tool, sees the data, and then writes a program that shows it the way it judges best. The program does not copy the numbers; it references them with `Query`, and the renderer gets them from your host.

```
tickets = Query("list_tickets", {status: "open"}, {rows: []})
root = Stack([LineChart(tickets.days, [Series("Open", tickets.counts)]), Metric("Open now", @Count(tickets.rows))])
```

This keeps data out of the model's output (fewer tokens, no copying mistakes) and lets the page refresh or filter without asking the model again.

## The prompt

Describe the tools with their `output_schema`, so the model knows the shape `Query` returns and the defaults to write:

```elixir
tools = [
  %{
    name: "list_tickets",
    description: "Tickets by status, with a count per day",
    input_schema: ~s({"type":"object","properties":{"status":{"type":"string","enum":["open","closed"]}},"required":["status"]}),
    output_schema: ~s({"type":"object","properties":{"rows":{"type":"array"},"days":{"type":"array","items":{"type":"string"}},"counts":{"type":"array","items":{"type":"number"}}}})
  }
]

system_prompt = OpenUI.Prompt.generate(MyApp.Library, tools: tools)
```

Pass schemas as JSON text (or `OpenUI.JSON.Object`) to keep the property order you wrote.

## The agent

Tools are `Jido.Action` modules. Have each one record its result for the renderer:

```elixir
defmodule MyApp.Tools.ListTickets do
  use Jido.Action,
    name: "list_tickets",
    description: "Tickets by status, with a count per day",
    schema: [status: [type: :string, required: true]]

  @impl true
  def run(params, context) do
    result = MyApp.Tickets.summary(params.status)
    MyApp.ToolResults.put(context.results, "list_tickets", params, result)
    {:ok, result}
  end
end
```

```elixir
alias Jido.AI.Reasoning.ReAct

{:ok, results} = MyApp.ToolResults.start_link()

answer =
  question
  |> ReAct.stream(
    %{model: model, system_prompt: system_prompt, tools: [MyApp.Tools.ListTickets], max_iterations: 4},
    context: %{results: results}
  )
  |> ReAct.collect_stream()

program = answer.result
```

## Answering Query

The renderer calls `tool_provider` for each `Query`. Answer from the results the agent already got, and fall back to running the tool:

```elixir
tool_provider = fn name, args ->
  case MyApp.ToolResults.fetch(results, name, args) do
    {:ok, result} -> {:ok, result}
    :error -> MyApp.Tools.run(name, args)
  end
end
```

```heex
<OpenUI.LiveView.renderer id="answer" response={@program} components={MyAppWeb.UI} tool_provider={@tool_provider} />
```

A tool the provider does not know should return `{:error, {:tool_not_found, names}}`; the error the model sees lists the names.

## Security

Every tool a program can query is a door into your data, reachable without the model. Check authorization inside each tool for the current user, as you would for any endpoint. Do not answer `Query` from a provider that trusts its arguments.
