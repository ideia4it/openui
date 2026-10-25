defmodule Support.Library do
  use OpenUI.Library, id: "support", version: "1.0.0", root: "Stack"

  component "Stack",
    description: "Lays out children in a column, or in a row for side-by-side metrics",
    props: [
      children: [type: {:array, :component}, required: true],
      direction: [type: {:enum, ["column", "row"]}, default: "column"]
    ]

  component "Card",
    description: "A titled block",
    props: [title: [type: :string, required: true], children: [type: {:array, :component}]]

  component "Text",
    description: "A paragraph",
    props: [
      text: [type: :string, required: true],
      variant: [type: {:enum, ["body", "muted"]}, default: "body"]
    ]

  component "Metric",
    description: "A labeled number",
    props: [label: [type: :string, required: true], value: [type: :number, required: true]]

  component "BarChart",
    description: "One bar per label, such as tickets per day or per priority",
    props: [
      labels: [type: {:array, :string}, required: true],
      values: [type: {:array, :number}, required: true],
      title: [type: :string]
    ]

  component "Table",
    description: "Rows of data, built from columns",
    props: [columns: [type: {:array, {:ref, "Col"}}, required: true]]

  component "Col",
    description: "One table column: a header and its cell values, top to bottom",
    props: [label: [type: :string, required: true], data: [type: {:array, :any}, required: true]]

  component "Button",
    description: "A clickable button",
    props: [
      label: [type: :string, required: true],
      action: [type: :action],
      variant: [type: {:enum, ["primary", "secondary"]}, default: "secondary"]
    ]

  group "Layout", ["Stack", "Card", "Text"]

  group "Data", ["Metric", "BarChart", "Table", "Col"],
    notes: ["Prefer a BarChart over a Table for counts per day or per category."]

  group "Actions", ["Button"],
    notes: [~s|Offer follow-up questions as Buttons with @ToAssistant("...").|]
end

defmodule Support.Tickets do
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
    {110, "Two-factor code rejected", "closed", "high", 5},
    {111, "Slow dashboard on large accounts", "open", "normal", 6},
    {112, "Wrong time zone in reports", "closed", "normal", 6}
  ]

  @doc "The tools for OpenUI.Prompt.generate/2, with their schemas."
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
      },
      %{
        name: "ticket_stats",
        description:
          "How many tickets are open and closed, and how many open tickets per priority: open_by_priority[i] counts priorities[i]",
        input_schema: ~s({"type":"object","properties":{}}),
        output_schema:
          ~s({"type":"object","properties":{"open":{"type":"number"},"closed":{"type":"number"},"priorities":{"type":"array","items":{"type":"string"}},"open_by_priority":{"type":"array","items":{"type":"number"}}}})
      }
    ]
  end

  @doc "Answers the tools for the renderer's tool_provider and for the agent."
  def run("list_tickets", args), do: {:ok, list(Map.get(args, "status", "open"))}
  def run("ticket_stats", _args), do: {:ok, stats()}
  def run(_name, _args), do: {:error, {:tool_not_found, ["list_tickets", "ticket_stats"]}}

  defp list(status) do
    tickets = Enum.filter(all(), &(&1.status == status))
    days = Enum.map(6..0//-1, &Date.add(Date.utc_today(), -&1))

    %{
      rows:
        tickets
        |> Enum.sort_by(& &1.opened_on, Date)
        |> Enum.map(&Map.take(&1, [:id, :subject, :priority, :opened_on])),
      days: Enum.map(days, &Calendar.strftime(&1, "%b %d")),
      counts: Enum.map(days, fn day -> Enum.count(tickets, &(&1.opened_on == day)) end)
    }
  end

  defp stats do
    priorities = ["high", "normal", "low"]
    open = Enum.filter(all(), &(&1.status == "open"))

    %{
      open: length(open),
      closed: Enum.count(all(), &(&1.status == "closed")),
      priorities: priorities,
      open_by_priority: Enum.map(priorities, fn p -> Enum.count(open, &(&1.priority == p)) end)
    }
  end

  defp all do
    for {id, subject, status, priority, days_ago} <- @tickets do
      %{
        id: id,
        subject: subject,
        status: status,
        priority: priority,
        opened_on: Date.add(Date.utc_today(), -days_ago)
      }
    end
  end
end

defmodule Support.UI do
  use OpenUI.LiveView.Components, library: Support.Library

  def stack(assigns) do
    ~H"""
    <div class={["stack", @direction == "row" && "stack-row"]}>{@children}</div>
    """
  end

  def card(assigns) do
    ~H"""
    <section class="card">
      <h3>{@title}</h3>
      {@children}
    </section>
    """
  end

  def text(assigns), do: ~H|<p class={["text", @variant == "muted" && "muted"]}>{@text}</p>|

  def metric(assigns) do
    ~H"""
    <div class={["metric", @loading && "loading"]}>
      <span class="metric-value">{number(@value)}</span>
      <span class="metric-label">{@label}</span>
    </div>
    """
  end

  def bar_chart(assigns) do
    values = Enum.map(list_or_empty(assigns.values), &if(is_number(&1), do: &1, else: 0))
    highest = Enum.max([1 | values])

    bars =
      Enum.zip_with(list_or_empty(assigns.labels), values, &{&1, &2, round(&2 / highest * 100)})

    assigns = assign(assigns, :bars, bars)

    ~H"""
    <figure class={["bar-chart", @loading && "loading"]}>
      <figcaption :if={@title}>{@title}</figcaption>
      <div class="bars">
        <div :for={{label, value, height} <- @bars} class="bar" title={"#{label}: #{number(value)}"}>
          <span class="bar-value">{number(value)}</span>
          <span class="bar-fill" style={"height: #{height}%"}></span>
          <span class="bar-label">{label}</span>
        </div>
      </div>
    </figure>
    """
  end

  def table(assigns), do: ~H|<div class={["table", @loading && "loading"]}>{@columns}</div>|

  def col(assigns) do
    ~H"""
    <div class="col">
      <div class="cell head">{@label}</div>
      <div :for={value <- list_or_empty(@data)} class="cell">{cell(value)}</div>
    </div>
    """
  end

  def button(assigns) do
    ~H"""
    <button type="button" class={["button", @variant == "primary" && "primary"]} {@action || []}>{@label}</button>
    """
  end

  # Query results reach the components unchecked, so a list prop may hold anything.
  defp list_or_empty(values) when is_list(values), do: values
  defp list_or_empty(_values), do: []

  defp number(value) when is_float(value) and value == trunc(value), do: trunc(value)
  defp number(value), do: value

  defp cell(nil), do: ""
  defp cell(value) when is_binary(value) or is_number(value), do: number(value)
  defp cell(value), do: JSON.encode!(value)
end
