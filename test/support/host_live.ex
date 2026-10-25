defmodule OpenUI.Test.HostLive do
  @moduledoc false
  # A host page: renders one program and forwards every {:openui, ...}
  # message to the test process.
  use Phoenix.LiveView

  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       test_pid: session["test_pid"],
       response: session["response"],
       streaming: session["streaming"],
       tools: OpenUI.LiveCase.tools(session["tools_id"]),
       components: session["components"],
       unknown_slot?: session["unknown_slot"]
     )}
  end

  def render(assigns) do
    ~H"""
    <OpenUI.LiveView.renderer
      id="p"
      response={@response}
      components={@components}
      tool_provider={@tools}
      streaming={@streaming}
    >
      <:unknown :if={@unknown_slot?} :let={error}><p class="unknown">{error.code}</p></:unknown>
    </OpenUI.LiveView.renderer>
    """
  end

  def handle_info({:set_response, response, streaming}, socket),
    do: {:noreply, assign(socket, response: response, streaming: streaming)}

  def handle_info({:openui, _id, _payload} = message, socket) do
    send(socket.assigns.test_pid, message)
    {:noreply, socket}
  end
end
