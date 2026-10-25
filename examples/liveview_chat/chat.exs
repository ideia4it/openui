defmodule Support.ChatLive do
  @moduledoc """
  The chat page both scripts start. The assistant module, set in the
  `:support_example` application env, implements `answer(transcript, reply_to)`:
  it sends `{:answer_chunk, text_so_far}` to `reply_to` while the model writes
  and returns `{:ok, text}` or `{:error, reason}`.
  """

  use Phoenix.LiveView

  def model! do
    System.get_env("OPENUI_EXAMPLE_MODEL") ||
      raise "set OPENUI_EXAMPLE_MODEL to a ReqLLM model spec, such as openrouter:<provider>/<model>"
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, messages: [], busy?: false, page_title: "Support assistant")}
  end

  def handle_event("ask", %{"question" => question}, socket) do
    case String.trim(question) do
      "" -> {:noreply, socket}
      question -> {:noreply, ask(socket, question)}
    end
  end

  def handle_info({:openui, _id, %OpenUI.Event{type: "continue_conversation"} = event}, socket) do
    {:noreply, ask(socket, OpenUI.Message.from_event(event))}
  end

  def handle_info({:openui, id, {:errors, errors}}, socket) do
    for error <- errors, do: IO.puts("#{id}: #{JSON.encode!(OpenUI.Error.to_map(error))}")
    {:noreply, socket}
  end

  def handle_info({:openui, _id, _state_or_event}, socket), do: {:noreply, socket}

  def handle_info({:answer_chunk, text}, socket) do
    {:noreply, update_answer(socket, body: text)}
  end

  def handle_async(:answer, {:ok, {:ok, text}}, socket) do
    IO.puts("\n#{text}\n")
    {:noreply, socket |> update_answer(body: text, streaming?: false) |> assign(busy?: false)}
  end

  def handle_async(:answer, {:ok, {:error, reason}}, socket), do: failed(socket, reason)
  def handle_async(:answer, {:exit, reason}, socket), do: failed(socket, reason)

  # A click while an answer is still streaming is dropped, so turns never interleave.
  defp ask(%{assigns: %{busy?: true}} = socket, _user_turn), do: socket

  defp ask(socket, user_turn) do
    turn = System.unique_integer([:positive])
    assistant = Application.fetch_env!(:support_example, :assistant)
    transcript = transcript(socket.assigns.messages) ++ [{:user, model_text(user_turn, :user)}]
    live_view = self()

    socket
    |> assign(busy?: true)
    |> assign(
      :messages,
      socket.assigns.messages ++
        [
          %{id: "user-#{turn}", role: :user, body: user_turn},
          %{id: "answer-#{turn}", role: :assistant, body: "", streaming?: true, error: nil}
        ]
    )
    |> start_async(:answer, fn -> assistant.answer(transcript, live_view) end)
  end

  defp transcript(messages), do: Enum.map(messages, &{&1.role, model_text(&1.body, &1.role)})

  defp model_text(body, role), do: OpenUI.Message.model_text(body, role)

  defp failed(socket, reason) do
    {:noreply,
     socket
     |> update_answer(streaming?: false, error: inspect(reason))
     |> assign(busy?: false)}
  end

  defp update_answer(socket, changes) do
    update(socket, :messages, fn messages ->
      List.update_at(messages, -1, &Map.merge(&1, Map.new(changes)))
    end)
  end

  def render(assigns) do
    ~H"""
    <style>
      :root { color-scheme: light dark; --line: #d4d4d8; --soft: #f4f4f5; --text: #18181b; --muted: #71717a; --accent: #6d28d9; }
      @media (prefers-color-scheme: dark) { :root { --line: #3f3f46; --soft: #27272a; --text: #fafafa; --muted: #a1a1aa; --accent: #a78bfa; } }
      body { margin: 0; font: 15px/1.5 system-ui, sans-serif; color: var(--text); background: Canvas; }
      .chat { max-width: 760px; margin: 0 auto; padding: 24px 16px 120px; }
      .chat h1 { font-size: 20px; margin: 0; }
      .chat > header p { color: var(--muted); margin: 4px 0 24px; }
      .user { margin: 24px 0 8px; padding: 8px 12px; background: var(--soft); border-radius: 8px; width: fit-content; max-width: 80%; margin-left: auto; }
      .failure { color: #dc2626; }
      .composer { position: fixed; bottom: 0; left: 0; right: 0; background: Canvas; border-top: 1px solid var(--line); }
      .composer form { max-width: 760px; margin: 0 auto; padding: 12px 16px; display: flex; gap: 8px; }
      .composer input { flex: 1; font: inherit; padding: 8px 12px; border: 1px solid var(--line); border-radius: 8px; background: Canvas; color: var(--text); }
      .stack { display: flex; flex-direction: column; gap: 12px; }
      .stack-row { flex-direction: row; flex-wrap: wrap; }
      .stack-row > * { flex: 1 1 140px; }
      .card { border: 1px solid var(--line); border-radius: 10px; padding: 12px 16px; display: flex; flex-direction: column; gap: 12px; }
      .card h3 { margin: 0; font-size: 15px; }
      .text { margin: 0; }
      .muted { color: var(--muted); }
      .metric { border: 1px solid var(--line); border-radius: 10px; padding: 12px 16px; display: flex; flex-direction: column; }
      .metric-value { font-size: 26px; font-weight: 600; }
      .metric-label { color: var(--muted); font-size: 13px; }
      .bar-chart { margin: 0; }
      .bar-chart figcaption { font-weight: 600; margin-bottom: 8px; }
      .bars { display: flex; align-items: flex-end; gap: 8px; height: 180px; }
      .bar { flex: 1; height: 100%; display: flex; flex-direction: column; justify-content: flex-end; align-items: center; gap: 4px; }
      .bar-fill { width: 100%; background: var(--accent); border-radius: 4px 4px 0 0; min-height: 2px; }
      .bar-value, .bar-label { font-size: 12px; color: var(--muted); white-space: nowrap; }
      .table { display: flex; overflow-x: auto; border: 1px solid var(--line); border-radius: 10px; }
      .col { flex: 1 1 auto; }
      .cell { padding: 6px 12px; white-space: nowrap; border-bottom: 1px solid var(--line); }
      .cell:last-child { border-bottom: 0; }
      .head { font-weight: 600; background: var(--soft); }
      .button, .composer button { font: inherit; padding: 6px 14px; border: 1px solid var(--line); border-radius: 8px; background: Canvas; color: var(--text); cursor: pointer; width: fit-content; }
      .primary, .composer button { background: var(--accent); border-color: var(--accent); color: white; }
      .loading, .composer button:disabled { opacity: .5; }
      .unknown { color: var(--muted); font-size: 13px; }
    </style>
    <main class="chat">
      <header>
        <h1>Support assistant</h1>
        <p>Ask about the support tickets. The answer is an OpenUI program, drawn as it arrives.</p>
      </header>
      <div id="messages">
        <%= for message <- @messages do %>
          <p :if={message.role == :user} id={message.id} class="user">
            {OpenUI.Message.parse(message.body).content}
          </p>
          <div :if={message.role == :assistant} id={message.id}>
            <OpenUI.LiveView.renderer
              id={"#{message.id}-program"}
              response={message.body}
              components={Support.UI}
              tool_provider={&Support.Tickets.run/2}
              streaming={message.streaming?}
            >
              <:unknown :let={error}><p class="unknown">{error.message}</p></:unknown>
            </OpenUI.LiveView.renderer>
            <p :if={message.streaming? and message.body == ""} class="muted">Thinking...</p>
            <p :if={message.error} class="failure">The model failed: {message.error}</p>
          </div>
        <% end %>
      </div>
    </main>
    <div class="composer">
      <form id="question-form" phx-submit="ask">
        <input
          id={"question-#{length(@messages)}"}
          name="question"
          placeholder="Ask about the tickets"
          autocomplete="off"
          disabled={@busy?}
          value=""
        />
        <button type="submit" disabled={@busy?}>Send</button>
      </form>
    </div>
    """
  end
end
