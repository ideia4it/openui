# Stored programs

Programs are plain text. Store them with the answer and they render again later, on any client, as long as the catalog keeps the rules below.

## The message format

`OpenUI.Message` writes and reads the format of prompt.md, section 7: the program between marker lines the model never sees.

```elixir
stored =
  OpenUI.Message.build(
    content: program,
    context: [state],
    attributes: [{"library", "support@1.2.0"}],
    end: true
  )
```

```
]]>openui:content?library=support%401.2.0
root = Stack([open])
open = Metric("Open tickets", 12)
]]>openui:context
[{"$tab":"open"}]
]]>openui:end
```

- `content`: the program, or prose with fenced programs.
- `context`: anything the host wants; the renderers store the page state here, as `[state]`.
- `end`: the stream finished. A message without it was cut, and still renders.

`OpenUI.Message.parse/2` reads it back. When a response was regenerated after a failure, the last `content` wins. The LiveView renderer accepts the stored form directly in `response` and restores the state from its context.

## State

The renderer sends `{:openui, id, {:state, state}}` whenever the person changes something. The state holds `$variables` with their values and form fields as `%{"value" => ..., "componentType" => ...}`, in the same shape the official React renderer uses, so a message stored by one renders with its state on the other.

Restoring never fails: keys the program no longer declares are kept, and values of an unexpected type are passed to the components as they are.

## What the model sees

History sent back to the model must not contain marker lines:

```elixir
OpenUI.Message.model_text(stored_answer, :assistant)
OpenUI.Message.model_text(stored_click, :user)
```

## Keeping old programs readable

Position is the meaning of an argument. A program stored today calls `Metric("Open tickets", 12)`; if `Metric` later takes `value` first, that program shows the wrong thing. The rules of prompt.md, section 3.2:

1. Only add props at the end. Never reorder or remove one.
2. A new required prop needs a default, since old programs cannot pass it.
3. Never name anything after a new built-in.

`mix openui.gen.spec MyApp.Library --out library.json --check` enforces the first two in CI by comparing the module with the committed spec.

## Edits

In edit mode the model answers with only the statements that changed. Merge them once the patch finished streaming:

```elixir
new_program = OpenUI.Edit.merge(current_program, patch)
```

A statement with an existing name replaces it, a new name is added, `name = null` deletes, and what `root` no longer reaches is removed. Store the merged program.
