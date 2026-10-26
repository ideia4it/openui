if Code.ensure_loaded?(Phoenix.Component) do
  defmodule OpenUI.LiveView do
    @moduledoc """
    Renders OpenUI programs in Phoenix LiveView.

        <OpenUI.LiveView.renderer
          id={"msg-\#{message.id}"}
          response={message.openui}
          components={MyAppWeb.AssistantUI}
          tool_provider={&MyApp.Tools.run/2}
          streaming={@streaming?}
        >
          <:unknown :let={error}><p>{error.message}</p></:unknown>
        </OpenUI.LiveView.renderer>

    `response` is the program, or a stored message with `]]>openui:` marker
    lines (`OpenUI.Message`). While `streaming` is true, pass the text
    accumulated so far; the renderer reads only what is new. Queries run when
    `streaming` turns false, or, with `queries={:on_statement}`, as soon as the
    statement holding each one is complete: for a `tool_provider` that answers
    from results the host already holds.

    `components` is a module that uses `OpenUI.LiveView.Components`. Each of
    its function components receives:

      * every prop of the catalog under its catalog name: plain values; a prop
        that takes components arrives as rendered HTML (or a list of it),
        rendered with `{@children}`; an action prop arrives as attributes for
        a button (`<button {@action || []}>`), or `nil` without an action; a
        bound prop arrives with its current value;
      * `@bind`, for components declared as fields: `id`, `name` and `value`
        attributes for the input (`<input {@bind} />`);
      * `@error`, the validation rule a field failed at the last submit
        (`"required"`, `"email"`, ...) or `nil`;
      * `@loading`, true while a query of the program is loading;
      * `@host`, the `host` map given to the renderer, for what the host
        knows and the program does not (a currency, the status of a record).
        A new map re-renders the program.

    `tool_provider` answers `Query` and `Mutation`: a map of tool names to
    `fn args -> {:ok, data} | {:error, reason} end`, or a function
    `(name, args) -> {:ok, data} | {:error, reason}` that returns
    `{:error, {:tool_not_found, names}}` for a tool it does not know.

    The LiveView that renders the program receives:

      * `{:openui, id, %OpenUI.Event{}}` for `@ToAssistant`, `@OpenUrl` and
        actions of the library;
      * `{:openui, id, {:state, state}}` when the person changes state; store it
        with `OpenUI.Message.build(content: program, context: [state])` and the
        renderer restores it when the message is shown again;
      * `{:openui, id, {:errors, errors}}` when the error list changes, `[]`
        once it recovers.

    Nothing a program contains can crash the page: a component that raises is
    left out and reported, an unknown component renders the `:unknown` slot
    (or nothing), and a failure of the renderer itself leaves the program
    empty and logs it. A catalog component cannot render a LiveComponent.
    """

    use Phoenix.Component

    attr(:id, :string, required: true)
    attr(:response, :string, required: true)
    attr(:components, :atom, required: true)
    attr(:tool_provider, :any, default: nil)
    attr(:streaming, :boolean, default: false)
    attr(:queries, :atom, default: :on_finish, values: [:on_finish, :on_statement])
    attr(:host, :map, default: %{})
    attr(:class, :string, default: nil)
    slot(:unknown)

    @doc "Renders a program. See the module documentation."
    def renderer(assigns) do
      ~H"""
      <.live_component
        module={OpenUI.LiveView.Program}
        id={@id}
        response={@response}
        components={@components}
        tool_provider={@tool_provider}
        streaming={@streaming}
        queries={@queries}
        host={@host}
        class={@class}
        unknown={@unknown}
      />
      """
    end
  end
end
