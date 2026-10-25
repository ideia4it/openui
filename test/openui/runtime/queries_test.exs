defmodule OpenUI.Runtime.QueriesTest do
  use ExUnit.Case, async: true

  defp start(source) do
    library = OpenUI.Conformance.library()

    {runtime, _effects} =
      library
      |> OpenUI.Runtime.new(fields: %{"Input" => [name: "name", type: "input"]})
      |> OpenUI.Runtime.load(OpenUI.Parser.parse(source, library))

    {runtime, _effects} = OpenUI.Runtime.finish(runtime)
    runtime
  end

  defp key_of(runtime, statement_id),
    do: OpenUI.Conformance.key_of(OpenUI.Runtime.tree(runtime), statement_id)

  defp metric_value(runtime) do
    %OpenUI.Element{props: %{"children" => children}} = OpenUI.Runtime.tree(runtime)
    Enum.find_value(children, &(&1.type == "Metric" && &1.props["value"]))
  end

  test "discards a result for arguments that changed while it was in flight" do
    runtime =
      start(~S"""
      $status = "open"
      root = Stack([filter, Metric("n", @Count(t.rows))])
      filter = Input("status", "S", $status)
      t = Query("list", {status: $status}, {rows: []})
      """)

    {runtime, [{:run_query, "t", "list", %{"status" => "closed"}}]} =
      OpenUI.Runtime.input(runtime, key_of(runtime, "filter"), "closed")

    {runtime, _} =
      OpenUI.Runtime.query_result(runtime, "t", %{"status" => "closed"}, {:ok, %{"rows" => [1]}})

    {runtime, _} =
      OpenUI.Runtime.query_result(
        runtime,
        "t",
        %{"status" => "open"},
        {:ok, %{"rows" => [1, 2, 3]}}
      )

    assert metric_value(runtime) == 1
  end

  test "keeps the defaults and names the tools when a tool does not exist" do
    runtime =
      start(~s|root = Stack([Metric("n", @Count(t.rows))])\nt = Query("missing", {}, {rows: []})|)

    {runtime, []} =
      OpenUI.Runtime.query_result(
        runtime,
        "t",
        %{},
        {:error, {:tool_not_found, ["list", "create"]}}
      )

    assert metric_value(runtime) == 0

    assert [
             %OpenUI.Error{
               code: "tool-not-found",
               source: :query,
               tool_name: "missing",
               hint: hint
             }
           ] =
             OpenUI.Runtime.query_status(runtime).errors

    assert hint =~ "list" and hint =~ "create"
  end

  test "rejects a second run of a mutation while the first is loading" do
    runtime =
      start(~S"""
      root = Stack([go])
      m = Mutation("create", {})
      go = Button("Go", @Run(m))
      """)

    {runtime, [{:run_mutation, _ref, "create", %{}}]} =
      OpenUI.Runtime.trigger(runtime, key_of(runtime, "go"), "action")

    assert {_runtime, []} = OpenUI.Runtime.trigger(runtime, key_of(runtime, "go"), "action")
  end

  test "schedules a refresh after each result of a query with an interval" do
    runtime =
      start(
        ~s|root = Stack([Metric("n", @Count(t.rows))])\nt = Query("list", {}, {rows: []}, 30)|
      )

    assert {_runtime, [{:schedule_refresh, "t", 30}]} =
             OpenUI.Runtime.query_result(runtime, "t", %{}, {:ok, %{"rows" => []}})
  end

  test "emits the error list only when it changes and signals recovery with an empty list" do
    runtime =
      start(~s|root = Stack([Metric("n", @Count(t.rows))])\nt = Query("list", {}, {rows: []})|)

    {runtime, _} = OpenUI.Runtime.query_result(runtime, "t", %{}, {:error, :timeout})

    assert {runtime, {:changed, [%OpenUI.Error{code: "tool-error"}]}} =
             OpenUI.Runtime.take_errors(runtime)

    assert {runtime, :unchanged} = OpenUI.Runtime.take_errors(runtime)
    {runtime, _} = OpenUI.Runtime.query_result(runtime, "t", %{}, {:ok, %{"rows" => []}})
    assert {_runtime, {:changed, []}} = OpenUI.Runtime.take_errors(runtime)
  end
end
