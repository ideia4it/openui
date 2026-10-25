defmodule OpenUI.RuntimeTest do
  use ExUnit.Case, async: true

  defp start(source, opts \\ []) do
    library = OpenUI.Conformance.library()

    opts =
      Keyword.merge(
        [fields: %{"Input" => [name: "name", type: "input"]}, forms: %{"Form" => "name"}],
        opts
      )

    {runtime, _effects} =
      library
      |> OpenUI.Runtime.new(opts)
      |> OpenUI.Runtime.load(OpenUI.Parser.parse(source, library))

    {runtime, _effects} = OpenUI.Runtime.finish(runtime)
    runtime
  end

  defp key_of(runtime, statement_id),
    do: OpenUI.Conformance.key_of(OpenUI.Runtime.tree(runtime), statement_id)

  test "replaces untouched defaults on a new parse and keeps what the person typed" do
    library = OpenUI.Conformance.library()
    parse = &OpenUI.Parser.parse(&1, library)
    runtime = OpenUI.Runtime.new(library, fields: %{"Input" => [name: "name", type: "input"]})

    {runtime, []} =
      OpenUI.Runtime.load(
        runtime,
        parse.(~s|$tab = "a"\nroot = Stack([i])\ni = Input("tab", "T", $tab)|)
      )

    {runtime, []} =
      OpenUI.Runtime.load(
        runtime,
        parse.(~s|$tab = "b"\nroot = Stack([i])\ni = Input("tab", "T", $tab)|)
      )

    {runtime, []} = OpenUI.Runtime.finish(runtime)
    assert OpenUI.Runtime.state(runtime)["$tab"] == "b"

    {runtime, []} = OpenUI.Runtime.input(runtime, key_of(runtime, "i"), "typed")

    {runtime, []} =
      OpenUI.Runtime.load(
        runtime,
        parse.(~s|$tab = "c"\nroot = Stack([i])\ni = Input("tab", "T", $tab)|)
      )

    assert OpenUI.Runtime.state(runtime)["$tab"] == "typed"
  end

  test "restores state saved by an older program without raising or dropping keys" do
    runtime =
      start(~s|$tab = "a"\nroot = Stack([Text($tab)])|, state: %{"$old" => 1, "$tab" => 5})

    assert runtime |> OpenUI.Runtime.state() |> Map.take(["$old", "$tab"]) == %{
             "$old" => 1,
             "$tab" => 5
           }

    assert %OpenUI.Element{type: "Stack"} = OpenUI.Runtime.tree(runtime)
  end

  test "blocks a send inside a form until every field passes" do
    runtime =
      start(~S"""
      root = Stack([Form("signup", [email, send])])
      email = Input("email", "E-mail", null, {required: true, email: true})
      send = Button("Send", @ToAssistant("Send"))
      """)

    assert {runtime, []} = OpenUI.Runtime.trigger(runtime, key_of(runtime, "send"), "action")
    assert OpenUI.Runtime.field_error(runtime, key_of(runtime, "email")) == "required"

    {runtime, []} = OpenUI.Runtime.input(runtime, key_of(runtime, "email"), "a@b")
    assert OpenUI.Runtime.field_error(runtime, key_of(runtime, "email")) == "email"

    {runtime, []} = OpenUI.Runtime.input(runtime, key_of(runtime, "email"), "a@b.co")
    assert OpenUI.Runtime.field_error(runtime, key_of(runtime, "email")) == nil

    assert {_runtime,
            [{:emit, %OpenUI.Event{type: "continue_conversation", form_name: "signup"} = event}]} =
             OpenUI.Runtime.trigger(runtime, key_of(runtime, "send"), "action")

    assert event.form_state == %{
             "signup" => %{"email" => %{"value" => "a@b.co", "componentType" => "input"}}
           }
  end

  test "blocks a library action or a mutation inside a form until every field passes" do
    runtime =
      start(~S"""
      root = Stack([Form("invite", [email, copy, save])])
      email = Input("email", "E-mail", null, {required: true})
      copy = Button("Copy", @CopyToClipboard("Join us"))
      save = Button("Save", @Run(m))
      m = Mutation("create", {})
      """)

    assert {runtime, []} = OpenUI.Runtime.trigger(runtime, key_of(runtime, "copy"), "action")
    assert {runtime, []} = OpenUI.Runtime.trigger(runtime, key_of(runtime, "save"), "action")
    assert OpenUI.Runtime.field_error(runtime, key_of(runtime, "email")) == "required"

    {runtime, []} = OpenUI.Runtime.input(runtime, key_of(runtime, "email"), "a@b.co")

    assert {_runtime, [{:emit, %OpenUI.Event{type: "CopyToClipboard"}}]} =
             OpenUI.Runtime.trigger(runtime, key_of(runtime, "copy"), "action")

    assert {_runtime, [{:run_mutation, _run_ref, "create", %{}}]} =
             OpenUI.Runtime.trigger(runtime, key_of(runtime, "save"), "action")
  end

  test "runs a plan that sends nothing inside a form without checking its fields" do
    runtime =
      start(~S"""
      $note = "draft"
      root = Stack([Form("invite", [email, clear]), Text($note)])
      email = Input("email", "E-mail", null, {required: true})
      clear = Button("Clear", @Set($note, "cleared"))
      """)

    assert {runtime, []} = OpenUI.Runtime.trigger(runtime, key_of(runtime, "clear"), "action")
    assert OpenUI.Runtime.state(runtime)["$note"] == "cleared"
    assert OpenUI.Runtime.field_error(runtime, key_of(runtime, "email")) == nil
  end

  test "records nothing for a change on a component the host did not declare as a field" do
    runtime =
      start(~S"""
      root = Stack([size])
      size = Select("size", [SelectItem("s", "Small")])
      """)

    assert {runtime, []} = OpenUI.Runtime.input(runtime, key_of(runtime, "size"), "s")
    assert OpenUI.Runtime.state(runtime) == %{}
  end

  test "binds a field written with an inline assignment to its $variable" do
    runtime =
      start(~S"""
      root = Stack([search, Text($query = "")])
      search = Input("query", "Search", $query = "")
      """)

    {runtime, []} = OpenUI.Runtime.input(runtime, key_of(runtime, "search"), "cut")

    %OpenUI.Element{props: %{"children" => [_search, text]}} = OpenUI.Runtime.tree(runtime)
    assert OpenUI.Runtime.state(runtime)["$query"] == "cut"
    assert text.props["text"] == "cut"
  end

  test "ignores input, field reads and refreshes for an element or a query an edit removed" do
    library = OpenUI.Conformance.library()

    runtime =
      start(~S"""
      root = Stack([Metric("n", @Count(t.rows)), name])
      name = Input("name", "Name")
      t = Query("list", {}, {rows: []}, 30)
      """)

    name_key = key_of(runtime, "name")

    {runtime, [{:schedule_refresh, "t", 30}]} =
      OpenUI.Runtime.query_result(runtime, "t", %{}, {:ok, %{"rows" => []}})

    {runtime, []} =
      OpenUI.Runtime.load(runtime, OpenUI.Parser.parse(~s|root = Stack([Text("Done")])|, library))

    assert {^runtime, []} = OpenUI.Runtime.input(runtime, name_key, "Ana")
    assert OpenUI.Runtime.field_value(runtime, name_key) == nil
    assert {^runtime, []} = OpenUI.Runtime.refresh(runtime, "t")
  end

  test "reports a root that does not evaluate to a component" do
    library = OpenUI.Conformance.library()

    program =
      OpenUI.Parser.parse(~s|$show = false\nroot = $show ? Stack([Text("a")]) : null|, library)

    {runtime, []} = library |> OpenUI.Runtime.new() |> OpenUI.Runtime.load(program)

    assert OpenUI.Runtime.tree(runtime) == nil

    assert [%OpenUI.Error{code: "no-root", statement_id: "root"}] =
             OpenUI.Runtime.render_errors(runtime)
  end

  test "starts a new response clean, clearing the reported errors and ignoring late tool results" do
    runtime =
      start(~S"""
      root = Stack([Metric("n", @Count(t.rows)), go])
      t = Query("list", {}, {rows: []})
      m = Mutation("create", {})
      go = Button("Go", @Run(m))
      """)

    {runtime, [{:run_mutation, run_ref, "create", %{}}]} =
      OpenUI.Runtime.trigger(runtime, key_of(runtime, "go"), "action")

    {runtime, []} = OpenUI.Runtime.query_result(runtime, "t", %{}, {:error, :timeout})

    {runtime, {:changed, [%OpenUI.Error{code: "tool-error"}]}} =
      OpenUI.Runtime.take_errors(runtime)

    runtime = OpenUI.Runtime.restart(runtime)

    assert {runtime, {:changed, []}} = OpenUI.Runtime.take_errors(runtime)
    assert {runtime, :unchanged} = OpenUI.Runtime.take_errors(runtime)
    assert {^runtime, []} = OpenUI.Runtime.mutation_result(runtime, run_ref, {:ok, %{}})
    assert OpenUI.Runtime.state(runtime) == %{}
  end

  test "inspects as its state and field errors, leaving the library and the program out" do
    runtime = start(~s|$tab = "a"\nroot = Stack([Text($tab)])|)

    assert inspect(runtime) ==
             ~s|#OpenUI.Runtime<store: %{"$tab" => "a"}, finished?: true, field_errors: %{}, ...>|
  end
end
