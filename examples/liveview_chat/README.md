# LiveView chat

A support assistant chat page. The model answers with an OpenUI program that the page draws while it streams. Each script runs alone with `Mix.install`; no Phoenix project needed.

| File | What it is |
| --- | --- |
| `catalog.exs` | The catalog (`Support.Library`), its components (`Support.UI`) and the tickets the tools read, kept in memory |
| `chat.exs` | The chat page both scripts start |
| `req_llm.exs` | Calls the model with [ReqLLM](https://hex.pm/packages/req_llm). The model reads data only through `Query` |
| `jido_ai.exs` | A [Jido.AI](https://hex.pm/packages/jido_ai) ReAct agent. The model calls `list_tickets` and `ticket_stats` to see the data, then writes a program that reads it with `Query` |

## Run

Pick any model ReqLLM supports and set its provider key, such as `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`:

```bash
export OPENUI_EXAMPLE_MODEL="openrouter:<provider>/<model>"
elixir examples/liveview_chat/req_llm.exs
# or
elixir examples/liveview_chat/jido_ai.exs
```

Open http://localhost:4000 and try:

- Show open tickets as a chart
- How many tickets are open per priority?
- List the oldest open tickets, with a button to show closed ones

The first run downloads and compiles the dependencies.

### Jido.AI with OpenRouter

Jido.AI 2.4.0 sends `previous_response_id` on the turn after a tool call, and ReqLLM's OpenRouter provider rejects it. Go through OpenRouter's OpenAI-compatible API instead:

```bash
export OPENUI_EXAMPLE_MODEL="openrouter:<provider>/<model>"
OPENUI_EXAMPLE_BASE_URL=https://openrouter.ai/api/v1 OPENAI_API_KEY="$OPENROUTER_API_KEY" \
  elixir examples/liveview_chat/jido_ai.exs
```

## What to look at

- **Streaming.** The page draws a valid program after every chunk: cards and charts show up while the model is still writing.
- **Query.** Data never goes through the model's output. `Query("list_tickets", ...)` runs when the stream ends, through the `tool_provider` (`Support.Tickets.run/2`).
- **Buttons.** `@ToAssistant("...")` sends your LiveView an `%OpenUI.Event{}`; the page turns it into the next question with `OpenUI.Message.from_event/1`.
- **Errors.** Program mistakes are printed to the terminal as the JSON the model would read. Unknown components show the `:unknown` slot.
