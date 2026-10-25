Mix.install([
  {:openui, path: Path.expand("../..", __DIR__)},
  {:bandit, "~> 1.8"},
  {:req_llm, "~> 1.27"}
])

defmodule Example.Tickets do
  @tickets [
    {101, "Login fails with single sign-on", "open", "high", 0},
    {102, "Invoice PDF shows the wrong address", "open", "normal", 1},
    {103, "Export to CSV times out", "open", "high", 1},
    {104, "Typo on the pricing page", "closed", "low", 2},
    {105, "Password reset e-mail never arrives", "open", "high", 2},
    {106, "Dark mode colors in the editor", "open", "low", 3},
    {107, "Webhook retries twice", "closed", "normal", 3},
    {108, "Cannot remove a team member", "open", "normal", 4},
    {109, "Search ignores accents", "open", "normal", 5},
    {110, "Two-factor code rejected", "closed", "high", 5}
  ]

  def tools do
    [
      %{
        name: "list_tickets",
        description:
          "Tickets with a status, oldest first, and how many of them were opened on each of the last 7 days",
        input_schema:
          ~s({"type":"object","properties":{"status":{"type":"string","enum":["open","closed"]}},"required":["status"]}),
        output_schema:
          ~s({"type":"object","properties":{"rows":{"type":"array","items":{"type":"object","properties":{"id":{"type":"number"},"subject":{"type":"string"},"priority":{"type":"string"},"opened_on":{"type":"string"}}}},"days":{"type":"array","items":{"type":"string"}},"counts":{"type":"array","items":{"type":"number"}}}})
      }
    ]
  end

  def run("list_tickets", args), do: {:ok, list(Map.get(args, "status", "open"))}
  def run(_name, _args), do: {:error, {:tool_not_found, ["list_tickets"]}}

  defp list(status) do
    today = Date.utc_today()
    days = Enum.map(6..0//-1, &Date.add(today, -&1))

    tickets =
      for {id, subject, ^status, priority, days_ago} <- @tickets,
          do: %{
            id: id,
            subject: subject,
            priority: priority,
            opened_on: Date.add(today, -days_ago)
          }

    %{
      rows:
        tickets
        |> Enum.sort_by(& &1.opened_on, Date)
        |> Enum.map(&Map.update!(&1, :opened_on, fn day -> Date.to_iso8601(day) end)),
      days: Enum.map(days, &Calendar.strftime(&1, "%b %d")),
      counts: Enum.map(days, fn day -> Enum.count(tickets, &(&1.opened_on == day)) end)
    }
  end
end

defmodule Example.Assistant do
  alias ReqLLM.Context

  @library_path Path.expand("library.json", __DIR__)

  def library_path, do: @library_path

  def stream_answer(turns, on_token) do
    {:ok, library} = @library_path |> File.read!() |> OpenUI.Library.from_spec()
    system_prompt = OpenUI.Prompt.generate(library, tools: Example.Tickets.tools())
    context = Context.new([Context.system(system_prompt) | Enum.map(turns, &message/1)])

    with {:ok, response} <- ReqLLM.stream_text(System.fetch_env!("OPENUI_EXAMPLE_MODEL"), context) do
      text =
        response
        |> ReqLLM.StreamResponse.tokens()
        |> Enum.reduce("", fn token, text ->
          on_token.(token)
          text <> token
        end)

      IO.puts("\n#{text}\n")
    end
  end

  # The app sends a click as the renderer's event; the backend owns how the model reads it.
  defp message(%{"role" => "user", "event" => event}) do
    %OpenUI.Event{
      type: event["type"],
      human_friendly_message: event["humanFriendlyMessage"] || "",
      params: event["params"] || %{},
      form_state: event["formState"] || %{},
      form_name: event["formName"]
    }
    |> OpenUI.Message.from_event()
    |> OpenUI.Message.model_text(:user)
    |> Context.user()
  end

  defp message(%{"role" => "user", "text" => text}), do: Context.user(text)

  defp message(%{"role" => "assistant", "text" => text}),
    do: Context.assistant(OpenUI.Message.model_text(text, :assistant))
end

defmodule Example.Router do
  use Plug.Router

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: JSON)
  plug(:dispatch)

  get "/library.json" do
    conn
    |> put_resp_content_type("application/json")
    |> send_file(200, Example.Assistant.library_path())
  end

  post "/chat" do
    conn = conn |> put_resp_content_type("text/plain") |> send_chunked(200)

    case Example.Assistant.stream_answer(conn.body_params["turns"], &chunk(conn, &1)) do
      :ok ->
        conn

      {:error, reason} ->
        IO.warn("model failed: #{inspect(reason)}", [])
        conn
    end
  end

  # Check the user's authorization here in a real app: a program can call any tool.
  post "/tools/:name" do
    case Example.Tickets.run(name, conn.body_params) do
      {:ok, result} ->
        conn |> put_resp_content_type("application/json") |> send_resp(200, JSON.encode!(result))

      {:error, {:tool_not_found, names}} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, JSON.encode!(%{error: "tool not found", tools: names}))
    end
  end
end

System.fetch_env!("OPENUI_EXAMPLE_MODEL")
{:ok, _} = Bandit.start_link(plug: Example.Router, port: 4000, ip: :loopback)
IO.puts("Backend on http://localhost:4000; run `bun run dev` for the app")
Process.sleep(:infinity)
