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

    {runtime, []} = OpenUI.Runtime.input(runtime, key_of(runtime, "email"), "a@b.co")

    assert {_runtime,
            [{:emit, %OpenUI.Event{type: "continue_conversation", form_name: "signup"} = event}]} =
             OpenUI.Runtime.trigger(runtime, key_of(runtime, "send"), "action")

    assert event.form_state == %{
             "signup" => %{"email" => %{"value" => "a@b.co", "componentType" => "input"}}
           }
  end
end
