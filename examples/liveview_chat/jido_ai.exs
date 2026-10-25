Mix.install([
  {:openui, path: Path.expand("../..", __DIR__)},
  {:phoenix_playground, "~> 0.1.9"},
  {:req_llm, "~> 1.27"},
  {:jido_ai, "~> 2.4"}
])

Code.require_file("catalog.exs", __DIR__)
Code.require_file("chat.exs", __DIR__)

defmodule Support.Tools.ListTickets do
  use Jido.Action,
    name: "list_tickets",
    description:
      "Tickets with a status, oldest first, and how many of them were opened on each of the last 7 days",
    schema: [status: [type: :string, required: true, doc: "open or closed"]]

  @impl true
  def run(params, _context), do: Support.Tickets.run("list_tickets", %{"status" => params.status})
end

defmodule Support.Tools.TicketStats do
  use Jido.Action,
    name: "ticket_stats",
    description:
      "How many tickets are open and closed, and how many open tickets per priority: open_by_priority[i] counts priorities[i]",
    schema: []

  @impl true
  def run(_params, _context), do: Support.Tickets.run("ticket_stats", %{})
end

defmodule Support.JidoAssistant do
  alias Jido.AI.Reasoning.ReAct

  @rules [
    "Call the tools first to see the data, then decide how to show it.",
    "Show data through Query so the page stays live; what the tools returned may be its defaults."
  ]

  def answer(transcript, reply_to) do
    config = %{
      model: model(),
      system_prompt:
        OpenUI.Prompt.generate(Support.Library,
          tools: Support.Tickets.tools(),
          additional_rules: @rules
        ),
      tools: [Support.Tools.ListTickets, Support.Tools.TicketStats],
      max_iterations: 4
    }

    transcript
    |> query()
    |> ReAct.stream(config)
    |> Enum.reduce(%{text: "", result: {:error, :no_answer}}, &follow(&1, &2, reply_to))
    |> Map.fetch!(:result)
  end

  # Jido.AI 2.4.0 sends previous_response_id after a tool call and ReqLLM's
  # OpenRouter provider rejects it, so OpenRouter goes through its OpenAI-compatible API.
  defp model do
    case System.get_env("OPENUI_EXAMPLE_BASE_URL") do
      nil ->
        Support.ChatLive.model!()

      base_url ->
        [_provider, id] = String.split(Support.ChatLive.model!(), ":", parts: 2)
        %{provider: :openai, id: id, base_url: base_url}
    end
  end

  # ReAct takes one user message, so earlier turns travel inside it.
  defp query([{:user, question}]), do: question

  defp query(transcript) do
    {earlier, [{:user, question}]} = Enum.split(transcript, -1)
    lines = Enum.map(earlier, fn {role, text} -> "#{role}: #{text}" end)
    Enum.join(["Earlier in this conversation:" | lines] ++ ["", question], "\n")
  end

  # Text written before a tool call is not the program, so each model turn starts over.
  defp follow(%{kind: :llm_started}, acc, _reply_to), do: %{acc | text: ""}

  defp follow(%{kind: :llm_delta, data: %{chunk_type: :content, delta: delta}}, acc, reply_to) do
    text = acc.text <> delta
    send(reply_to, {:answer_chunk, text})
    %{acc | text: text}
  end

  defp follow(%{kind: :request_completed, data: data}, acc, _reply_to) do
    result = Map.get(data, :result)
    %{acc | result: {:ok, if(is_binary(result), do: result, else: acc.text)}}
  end

  defp follow(%{kind: :request_failed, data: data}, acc, _reply_to) do
    %{acc | result: {:error, Map.get(data, :error)}}
  end

  defp follow(_event, acc, _reply_to), do: acc
end

Support.ChatLive.model!()
Application.put_env(:support_example, :assistant, Support.JidoAssistant)
PhoenixPlayground.start(live: Support.ChatLive, open_browser: false)
