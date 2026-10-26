# LiveView

`OpenUI.LiveView.renderer/1` draws a program with your function components. It needs `phoenix_live_view ~> 1.1`.

```heex
<OpenUI.LiveView.renderer
  id={"msg-#{@message.id}"}
  response={@message.openui}
  components={MyAppWeb.AssistantUI}
  tool_provider={&MyApp.Tools.run/2}
  streaming={@streaming?}
>
  <:unknown :let={error}><p class="text-xs text-gray-500">{error.message}</p></:unknown>
</OpenUI.LiveView.renderer>
```

| Attribute | Meaning |
| --- | --- |
| `id` | Unique per program on the page. It also names the messages your LiveView receives. |
| `response` | The program, or a stored message with `]]>openui:` marker lines (see [Stored programs](stored-programs.md)). |
| `components` | A module that uses `OpenUI.LiveView.Components`. |
| `tool_provider` | Answers `Query` and `Mutation` (see below). Optional. |
| `streaming` | `true` while the model is still writing. Queries run when it turns `false`, unless `queries` says otherwise. |
| `queries` | When queries run: `:on_finish` (default), once the stream ends; or `:on_statement`, as soon as the statement holding each one and every statement it reads are complete, for a `tool_provider` that answers from results you already hold. A query that reads a `$variable` or value the model has not finished writing waits for it. |
| `host` | A map every component receives as `@host`, for what your app knows and the program does not. A new map re-renders the program. Optional. |
| `class` | Class of the wrapper element. |
| `:unknown` slot | Shown where the model used a component the catalog does not have. Without it, nothing shows. |

Each program is a LiveComponent with its own state, so one page can hold a whole chat of answers.

## The components module

```elixir
defmodule MyAppWeb.AssistantUI do
  use OpenUI.LiveView.Components,
    library: MyApp.Library,
    fields: %{"Input" => [name: "name", type: "input"], "Select" => [name: "name", type: "select"]},
    forms: %{"Form" => "name"}

  def form(assigns), do: ~H|<fieldset>{@children}</fieldset>|

  def input(assigns) do
    ~H"""
    <label>
      {@placeholder}
      <input type="text" {@bind} />
      <span :if={@error}>{error_text(@error)}</span>
    </label>
    """
  end

  # ...one function per catalog component
end
```

Every catalog component needs a function named after it in snake case (`LineChart` is `line_chart/1`), or the module does not compile.

- `fields` names the components that are form fields: the prop holding the field name, and the component type stored with its value. A field may add `rules: "prop"` when its validation rules are not in a prop called `rules`.
- `forms` names the components that give a form name to their subtree, and the prop that holds it.

The renderer wraps the program in a `<form>`. Render a form component as a `<fieldset>` or a `<div>`, never a nested `<form>`.

## Assigns

Each function receives:

- **Every catalog prop by its name**, as a plain value. A prop that takes components arrives as rendered HTML (a list of it for a list prop): render it with `{@children}`. Data that lands there at runtime, such as a query result written in a children list, is left out; text and numbers show as text. A bound prop arrives with its current value.
- **Action props as button attributes**: `<button {@action || []}>`. The attribute list is `nil` when the model gave no action. You never deal with `phx-click` or `phx-target`.
- **`@bind`** for field components: `id`, `name` and `value` for the input, `<input {@bind} />`. Typing updates the bound `$variable` or the form field.
- **`@error`** for field components: the validation rule the field failed at the last submit (`"required"`, `"email"`, `"minLength"`...), or `nil`. Write the message in your own language.
- **`@loading`**: true while a query of the program is loading.
- **`@host`**: the `host` map of the renderer, `%{}` without one. Use it for data the program does not carry, such as a currency or the status of a record the person can act on.

So `bind`, `loading`, `error` and `host` cannot be catalog prop names.

An action inside a form that sends something (`@ToAssistant`, a library action or a mutation) runs only when every field of that form passes its rules.

## Messages to your LiveView

```elixir
def handle_info({:openui, _id, %OpenUI.Event{type: "continue_conversation"} = event}, socket) do
  {:noreply, ask(socket, OpenUI.Message.from_event(event))}
end

def handle_info({:openui, id, {:state, state}}, socket) do
  {:noreply, save_state(socket, id, state)}
end

def handle_info({:openui, _id, {:errors, errors}}, socket) do
  {:noreply, assign(socket, :openui_errors, errors)}
end
```

- `%OpenUI.Event{}`: `@ToAssistant` (`type: "continue_conversation"`), `@OpenUrl` (`"open_url"`) and actions of your library (their own name). It carries the form state as of when the action ran.
- `{:state, state}`: the person changed something. Store it to restore the program later, including after a reconnect: the program state lives in the LiveComponent, so without it a reconnect loses what the person typed.
- `{:errors, errors}`: the error list changed; `[]` means it recovered. Send it back to the model in the next request when you want it to fix its program.

## Query and Mutation

`Query("tool", args, defaults)` and `Mutation("tool", args)` call your tools through `tool_provider`:

```elixir
# a map of tools
tool_provider = %{"list_tickets" => fn args -> {:ok, MyApp.Tickets.list(args)} end}

# or one function
def run("list_tickets", args), do: {:ok, MyApp.Tickets.list(args)}
def run(_name, _args), do: {:error, {:tool_not_found, ["list_tickets"]}}
```

Each call runs in its own task with `start_async`. A query runs when the stream ends (or, with `queries={:on_statement}`, as soon as its statement and what it reads are complete) and again when a `$variable` written in its arguments changes; a result for arguments that changed meanwhile is dropped. A query with a refresh interval runs again on a timer. An exception in a tool becomes the query's or mutation's error; the page stays up.

Results can be any Elixir data: atom keys, `Decimal`, `Date` and structs are turned into JSON-like values.

## What it does not do

- A catalog component cannot render a LiveComponent: the renderer turns each component into HTML inside a rescue, and a LiveComponent cannot be turned into HTML. One that tries is dropped and reported.
- A component that changes is sent again whole; there is no diff inside it.
