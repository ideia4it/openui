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

  defp texts(runtime) do
    %OpenUI.Element{props: %{"children" => children}} = OpenUI.Runtime.tree(runtime)
    for %OpenUI.Element{type: "Text", props: props} <- children, do: props["text"]
  end

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

  test "fetches nothing while the stream is open and the latest arguments when it ends" do
    library = OpenUI.Conformance.library()

    program =
      OpenUI.Parser.parse(
        ~S"""
        $status = "open"
        root = Stack([filter, Metric("n", @Count(t.rows))])
        filter = Input("status", "S", $status)
        t = Query("list", {status: $status}, {rows: []})
        """,
        library
      )

    {runtime, []} =
      library
      |> OpenUI.Runtime.new(fields: %{"Input" => [name: "name", type: "input"]})
      |> OpenUI.Runtime.load(program)

    assert {runtime, []} = OpenUI.Runtime.input(runtime, key_of(runtime, "filter"), "closed")

    assert {_runtime, [{:run_query, "t", "list", %{"status" => "closed"}}]} =
             OpenUI.Runtime.finish(runtime)
  end

  describe "query timing" do
    defp streamed(text) do
      library = OpenUI.Conformance.library()

      library
      |> OpenUI.Stream.new()
      |> OpenUI.Stream.push(text)
      |> OpenUI.Stream.program()
    end

    defp eager_runtime,
      do: OpenUI.Runtime.new(OpenUI.Conformance.library(), queries: :on_statement)

    test "runs a query as soon as its statement is complete while the stream is open" do
      {_runtime, effects} =
        OpenUI.Runtime.load(
          eager_runtime(),
          streamed(~s|t = Query("list", {status: "open"}, {rows: []})\nroot = Stack([|)
        )

      assert {:run_query, "t", "list", %{"status" => "open"}} in effects
    end

    test "does not run a query whose statement is still being written" do
      {_runtime, effects} =
        OpenUI.Runtime.load(eager_runtime(), streamed(~s|t = Query("list", {status: "op|))

      refute Enum.any?(effects, &match?({:run_query, _, _, _}, &1))
    end

    test "does not run the query again at finish when its arguments did not change" do
      {runtime, [_run]} =
        OpenUI.Runtime.load(
          eager_runtime(),
          streamed(~s|t = Query("list", {status: "open"}, {rows: []})\nroot = Stack([|)
        )

      {runtime, _effects} =
        OpenUI.Runtime.load(
          runtime,
          streamed(
            ~s|t = Query("list", {status: "open"}, {rows: []})\nroot = Stack([Metric("n", @Count(t.rows))])\n|
          )
        )

      {_runtime, effects} = OpenUI.Runtime.finish(runtime)
      refute Enum.any?(effects, &match?({:run_query, "t", _, _}, &1))
    end

    test "runs the query again when a later statement changes its arguments" do
      query = ~s|t = Query("list", {status: $status}, {rows: []})\n|

      {runtime, _effects} = OpenUI.Runtime.load(eager_runtime(), streamed(query <> "root = "))

      {_runtime, effects} =
        OpenUI.Runtime.load(runtime, streamed(query <> ~s|$status = "closed"\nroot = |))

      assert {:run_query, "t", "list", %{"status" => "closed"}} in effects
    end
  end

  test "asks for a query written without arguments, or without a tool, with empty ones" do
    library = OpenUI.Conformance.library()

    program =
      OpenUI.Parser.parse(
        ~S"""
        root = Stack([Metric("n", @Count(t.rows) + @Count(u.rows))])
        t = Query("list")
        u = Query()
        """,
        library
      )

    {runtime, []} = library |> OpenUI.Runtime.new() |> OpenUI.Runtime.load(program)

    {_runtime, effects} = OpenUI.Runtime.finish(runtime)
    assert effects == [{:run_query, "t", "list", %{}}, {:run_query, "u", "", %{}}]
  end

  test "fetches a query again when a button runs it" do
    runtime =
      start(~S"""
      root = Stack([Metric("n", @Count(t.rows)), reload])
      t = Query("list", {}, {rows: []})
      reload = Button("Reload", @Run(t))
      """)

    {runtime, []} = OpenUI.Runtime.query_result(runtime, "t", %{}, {:ok, %{"rows" => [1]}})

    assert {runtime, [{:run_query, "t", "list", %{}}]} =
             OpenUI.Runtime.trigger(runtime, key_of(runtime, "reload"), "action")

    assert OpenUI.Runtime.query_status(runtime).refetching?
    assert metric_value(runtime) == 1
  end

  test "shows the status of a mutation before, while and after it runs" do
    runtime =
      start(~S"""
      root = Stack([Text(m.status), Text(m.error || "no error"), save])
      m = Mutation("create", {})
      save = Button("Save", @Run(m))
      """)

    assert texts(runtime) == ["idle", "no error"]

    {runtime, [{:run_mutation, run_ref, "create", %{}}]} =
      OpenUI.Runtime.trigger(runtime, key_of(runtime, "save"), "action")

    assert texts(runtime) == ["loading", "no error"]

    {runtime, []} = OpenUI.Runtime.mutation_result(runtime, run_ref, {:error, "quota exceeded"})

    assert ["error", message] = texts(runtime)
    assert message =~ "quota exceeded"

    {runtime, [{:run_mutation, run_ref, "create", %{}}]} =
      OpenUI.Runtime.trigger(runtime, key_of(runtime, "save"), "action")

    {runtime, []} = OpenUI.Runtime.mutation_result(runtime, run_ref, {:ok, %{"id" => 7}})
    assert texts(runtime) == ["success", "no error"]
  end

  test "skips the steps whose query or mutation an edit removed while a mutation ran" do
    library = OpenUI.Conformance.library()

    runtime =
      start(~S"""
      root = Stack([Metric("n", @Count(t.rows)), save])
      t = Query("list", {}, {rows: []})
      m = Mutation("create", {})
      audit = Mutation("log", {})
      save = Button("Save", Action([@Run(m), @Run(t), @Run(audit)]))
      """)

    {runtime, [{:run_mutation, run_ref, "create", %{}}]} =
      OpenUI.Runtime.trigger(runtime, key_of(runtime, "save"), "action")

    edited =
      OpenUI.Parser.parse(
        ~S"""
        root = Stack([Text("Saved")])
        m = Mutation("create", {})
        """,
        library
      )

    {runtime, []} = OpenUI.Runtime.load(runtime, edited)

    assert {_runtime, []} = OpenUI.Runtime.mutation_result(runtime, run_ref, {:ok, %{}})
  end

  test "loops over a query named like its own @Each loop variable, as the official renderer does" do
    runtime =
      start(~S"""
      root = Stack(@Each(tickets, "tickets", Text(tickets.title)))
      tickets = Query("list", {}, [{title: "Loading"}])
      """)

    assert texts(runtime) == ["Loading"]

    {runtime, []} =
      OpenUI.Runtime.query_result(
        runtime,
        "tickets",
        %{},
        {:ok, [%{"title" => "Leak"}, %{"title" => "Noise"}]}
      )

    assert texts(runtime) == ["Leak", "Noise"]
  end

  test "loops over a mutation result named like its own @Each loop variable, as the official renderer does" do
    runtime =
      start(~S"""
      root = Stack([save, Card("Saved", @Each(saved.data, "saved", Text(saved)))])
      saved = Mutation("create", {})
      save = Button("Save", @Run(saved))
      """)

    {runtime, [{:run_mutation, run_ref, "create", %{}}]} =
      OpenUI.Runtime.trigger(runtime, key_of(runtime, "save"), "action")

    {runtime, []} = OpenUI.Runtime.mutation_result(runtime, run_ref, {:ok, ["Ana", "Bia"]})

    %OpenUI.Element{props: %{"children" => [_save, card]}} = OpenUI.Runtime.tree(runtime)
    assert Enum.map(card.props["children"], & &1.props["text"]) == ["Ana", "Bia"]
  end
end
