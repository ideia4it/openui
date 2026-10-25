# Generating with ReqLLM

[ReqLLM](https://hex.pm/packages/req_llm) calls the model; OpenUI writes its system prompt and renders what it streams back.

## The request

```elixir
defmodule MyApp.Assistant do
  alias ReqLLM.Context

  # model is a ReqLLM model spec, such as "anthropic:<model-id>"
  def stream_answer(model, history, question, reply_to) do
    context =
      Context.new(
        [Context.system(OpenUI.Prompt.generate(MyApp.Library))] ++
          Enum.map(history, &to_message/1) ++
          [Context.user(question)]
      )

    {:ok, response} = ReqLLM.stream_text(model, context)

    response
    |> ReqLLM.StreamResponse.tokens()
    |> Enum.reduce("", fn token, text ->
      text = text <> token
      send(reply_to, {:answer_chunk, text})
      text
    end)
    |> then(&send(reply_to, {:answer_done, &1}))
  end

  # The model reads its earlier programs and the person's clicks without any
  # marker line (prompt.md, section 7.5).
  defp to_message(%{role: :assistant, body: body}), do: Context.assistant(OpenUI.Message.model_text(body, :assistant))
  defp to_message(%{role: :user, body: body}), do: Context.user(OpenUI.Message.model_text(body, :user))
end
```

Run it in a task from your LiveView and keep the text received so far:

```elixir
def handle_info({:answer_chunk, text}, socket), do: {:noreply, assign(socket, answer: text, streaming?: true)}
def handle_info({:answer_done, text}, socket), do: {:noreply, assign(socket, answer: text, streaming?: false)}
```

```heex
<OpenUI.LiveView.renderer id="answer" response={@answer} components={MyAppWeb.UI} streaming={@streaming?} />
```

The renderer reads only the new part of the text on each update and draws a valid page after every chunk.

## Storing the answer

```elixir
stored = OpenUI.Message.build(content: text, attributes: [{"library", "support@1.2.0"}], end: true)
```

When the person changes the page, the renderer sends `{:openui, id, {:state, state}}`. Store the state as the context of the same message so it comes back on reload:

```elixir
OpenUI.Message.build(content: text, context: [state], end: true)
```

## Clicks that continue the conversation

`@ToAssistant("Show the oldest")` sends your LiveView an `%OpenUI.Event{}`. `OpenUI.Message.from_event/1` turns it into the stored user turn, and `model_text(turn, :user)` into what the model reads: the message plus `context and form values = [...]`.

## Errors

The renderer sends `{:openui, id, {:errors, errors}}` when a program has mistakes. To let the model fix them, add the list to the next request:

```elixir
feedback = Enum.map(errors, &OpenUI.Error.to_map/1) |> JSON.encode!()
Context.user("Your last program had errors: " <> feedback)
```

Each error has a `hint`: the component's signature, or the names that exist.

## Tools

With `tools:` in `OpenUI.Prompt.generate/2` the prompt teaches `Query` and `Mutation`, and the renderer calls the tools through `tool_provider`. See [Jido.AI agents and Query](jido-ai.md) for a model that calls tools itself before writing the program.
