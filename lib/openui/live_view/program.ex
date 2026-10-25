if Code.ensure_loaded?(Phoenix.LiveComponent) do
  defmodule OpenUI.LiveView.Program do
    @moduledoc false
    # One rendered program: its stream, its runtime and the effects they ask
    # for. Rendered through OpenUI.LiveView.renderer/1.

    use Phoenix.LiveComponent

    require Logger

    alias OpenUI.{Library, Message, Runtime}
    alias OpenUI.LiveView.HTML
    alias OpenUI.Stream, as: ProgramStream
    alias Phoenix.HTML.Safe

    @impl true
    def mount(socket) do
      {:ok, assign(socket, runtime: nil, stream: nil, html: {:safe, ""}, renderer_errors: [])}
    end

    @impl true
    def update(assigns, socket) do
      socket =
        assign(socket, Map.take(assigns, [:id, :components, :tool_provider, :class, :unknown]))

      {:ok, guarded(socket, &receive_response(&1, assigns.response, assigns.streaming))}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div id={"program-#{@id}"} class={@class}>
        <form
          id={"program-#{@id}-form"}
          phx-change="openui:change"
          phx-submit="openui:noop"
          phx-target={@myself}
          phx-auto-recover="ignore"
          autocomplete="off"
        >
          {@html}
        </form>
      </div>
      """
    end

    @impl true
    def handle_event("openui:change", %{"_target" => ["openui", key], "openui" => values}, socket) do
      {:noreply, guarded(socket, &input(&1, key, Map.get(values, key)))}
    end

    def handle_event("openui:action", %{"key" => key, "prop" => prop}, socket) do
      {:noreply, guarded(socket, &trigger(&1, key, prop))}
    end

    def handle_event(_event, _params, socket), do: {:noreply, socket}

    # Last line of defense (language.md, section 10): a failure of this code,
    # or a broken components module, empties the program instead of crashing
    # the page.
    defp guarded(socket, fun) do
      fun.(socket)
    rescue
      exception ->
        Logger.error(
          "OpenUI could not render program #{socket.assigns[:id]}: " <>
            Exception.format(:error, exception, __STACKTRACE__)
        )

        assign(socket, html: {:safe, ""})
    end

    defp receive_response(socket, response, streaming?) do
      message = Message.parse(response || "", streaming: streaming?)
      socket = ensure_runtime(socket, message)
      stream = next_stream(socket, message.content)
      socket = assign(socket, stream: stream)
      {runtime, effects} = Runtime.load(socket.assigns.runtime, ProgramStream.program(stream))
      socket = assign(socket, runtime: runtime)

      socket =
        if streaming? or (ProgramStream.finished?(stream) and runtime.finished?),
          do: socket,
          else: finish(socket)

      socket
      |> run_effects(effects)
      |> rerender()
    end

    defp finish(socket) do
      stream = ProgramStream.finish(socket.assigns.stream)
      {runtime, effects} = Runtime.load(socket.assigns.runtime, ProgramStream.program(stream))
      {runtime, more} = Runtime.finish(runtime)

      socket
      |> assign(stream: stream, runtime: runtime)
      |> run_effects(effects ++ more)
    end

    # The first response restores the state stored in its context; a response
    # that does not continue the previous text starts over.
    defp ensure_runtime(%{assigns: %{runtime: nil}} = socket, message) do
      library = library(socket)
      components = socket.assigns.components

      runtime =
        Runtime.new(library,
          fields: components.__openui__(:fields),
          forms: components.__openui__(:forms),
          state: restored_state(message.context)
        )

      assign(socket, runtime: runtime, stream: ProgramStream.new(library))
    end

    defp ensure_runtime(socket, message) do
      if continues?(socket.assigns.stream, message.content) do
        socket
      else
        runtime = Runtime.restart(socket.assigns.runtime, restored_state(message.context))
        assign(socket, runtime: runtime, stream: ProgramStream.new(library(socket)))
      end
    end

    defp continues?(stream, content) do
      text = ProgramStream.text(stream)

      String.starts_with?(content, text) and
        not (ProgramStream.finished?(stream) and content != text)
    end

    defp next_stream(socket, content) do
      stream = socket.assigns.stream
      text = ProgramStream.text(stream)
      delta = binary_part(content, byte_size(text), byte_size(content) - byte_size(text))
      if delta == "", do: stream, else: ProgramStream.push(stream, delta)
    end

    defp library(socket), do: Library.resolve(socket.assigns.components.__openui__(:library))

    defp restored_state([state | _rest]) when is_map(state), do: state
    defp restored_state(state) when is_map(state), do: state
    defp restored_state(_none), do: %{}

    defp input(socket, key, value) do
      before = Runtime.state(socket.assigns.runtime)
      {runtime, effects} = Runtime.input(socket.assigns.runtime, key, value)

      socket
      |> assign(runtime: runtime)
      |> report_state(before)
      |> run_effects(effects)
      |> rerender()
    end

    defp trigger(socket, key, prop) do
      before = Runtime.state(socket.assigns.runtime)
      {runtime, effects} = Runtime.trigger(socket.assigns.runtime, key, prop)

      socket
      |> assign(runtime: runtime)
      |> report_state(before)
      |> run_effects(effects)
      |> rerender()
    end

    defp report_state(socket, before) do
      state = Runtime.state(socket.assigns.runtime)
      if state != before, do: notify(socket, {:state, state})
      socket
    end

    defp run_effects(socket, effects), do: Enum.reduce(effects, socket, &run_effect/2)

    defp run_effect({:emit, event}, socket) do
      notify(socket, event)
      socket
    end

    defp run_effect(_effect, socket), do: socket

    defp notify(socket, payload), do: send(self(), {:openui, socket.assigns.id, payload})

    defp rerender(socket) do
      {html, renderer_errors} =
        HTML.render(socket.assigns.runtime, socket.assigns.components,
          target: socket.assigns.myself,
          dom_id: "program-#{socket.assigns.id}",
          unknown: unknown_renderer(socket.assigns.unknown)
        )

      {runtime, errors} = Runtime.take_errors(socket.assigns.runtime, renderer_errors)
      if errors != :unchanged, do: notify(socket, {:errors, elem(errors, 1)})
      assign(socket, runtime: runtime, html: html, renderer_errors: renderer_errors)
    end

    defp unknown_renderer([]), do: nil
    defp unknown_renderer(nil), do: nil

    defp unknown_renderer(slot) do
      fn error ->
        {:safe, Safe.to_iodata(unknown_slot(%{slot: slot, error: error, __changed__: nil}))}
      end
    end

    defp unknown_slot(assigns), do: ~H"{render_slot(@slot, @error)}"
  end
end
