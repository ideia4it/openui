defmodule OpenUI.ParserTest do
  use ExUnit.Case, async: true

  alias OpenUI.Element
  alias OpenUI.Parser.{Expression, Lexer}

  defmodule TicketSummaryCatalog do
    @moduledoc false
    use OpenUI.Library, root: "Stack"

    component "Stack", props: [children: [type: {:array, :component}, required: true]]
    component "Text", props: [text: [type: :string, required: true]]

    function "Summary",
      params: [
        ids: [type: {:array, :number}, required: true],
        filter: [
          type:
            {:object,
             [
               status: [type: {:enum, ["open", "closed"]}, default: "open"],
               urgent: [type: :boolean],
               assignee: [type: :any],
               tags: [type: {:array, :string}]
             ]}
        ],
        limit: [type: :number, default: 10],
        verbose: [type: :boolean]
      ],
      returns: :string,
      impl: &__MODULE__.summary/1

    def summary(_args), do: ""
  end

  defp library, do: OpenUI.Conformance.library()
  defp fixture(id), do: File.read!(Path.join([OpenUI.Conformance.root(), id, "input.oui"]))

  # Shapes another client may write in a LibrarySpec that the DSL never
  # writes: no root component, an optional prop with a default (as pydantic
  # writes it) and an object that requires a key it does not describe.
  defp hand_written_library do
    {:ok, library} =
      OpenUI.Library.from_spec(~S"""
      {"schema": {
        "properties": {"Ticket": {"$ref": "#/$defs/Ticket"}, "Text": {"$ref": "#/$defs/Text"}},
        "$defs": {
          "Text": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
          "Ticket": {"type": "object",
                     "properties": {"title": {"anyOf": [{"type": "string"}, {"$ref": "#/$defs/Text"}]},
                                    "priority": {"type": "string", "enum": ["low", "high"], "default": "low"},
                                    "meta": {"type": "object", "required": ["id"]}},
                     "required": ["title"]}}}}
      """)

    library
  end

  defp errors(program), do: Enum.map(program.errors, &{&1.statement_id, &1.code, &1.path})
  defp messages(program), do: Enum.map(program.errors, & &1.message)
  defp children(program), do: program.root.props["children"]

  test "classifies statements, finds orphans and declares state defaults" do
    program = OpenUI.Parser.parse(fixture("evaluation/001-kind-classify"), library())
    assert Enum.map(program.queries, & &1.id) == ["data"]
    assert program.orphans == ["unused"]
    assert program.state == [{"$count", 2}]
  end

  test "auto-declares state names that are used but never declared" do
    program = OpenUI.Parser.parse(fixture("state/001-store-auto-declare"), library())
    assert program.state == [{"$v", "x"}, {"$name", nil}]
  end

  test "leaves a cycle unresolved where it closes" do
    assert OpenUI.Parser.parse(fixture("evaluation/003-ref-cycle"), library()).unresolved == ["a"]
  end

  test "drops an unknown component and reports it on its statement" do
    program = OpenUI.Parser.parse(fixture("errors/001-unknown-component-dropped"), library())

    assert [%OpenUI.Error{source: :parser, code: "unknown-component", statement_id: "chart"}] =
             program.errors
  end

  test "fills the structural fields of the error object" do
    program = OpenUI.Parser.parse(fixture("errors/005-shape-missing-required-metric"), library())
    assert [error] = program.errors

    assert error
           |> OpenUI.Error.to_map()
           |> Map.take(~w(source code statementId component path hint)) == %{
             "source" => "parser",
             "code" => "missing-required",
             "statementId" => "chart",
             "component" => "Metric",
             "path" => "/value",
             "hint" => "Signature: Metric(label*, value*). * marks required"
           }
  end

  test "falls back to the first call of the library root with a warning" do
    program = OpenUI.Parser.parse(fixture("entry/002-first-calls-root-component"), library())
    assert %Element{type: "Stack", statement_id: "page"} = program.root
    assert [%OpenUI.Error{code: "no-root", severity: :warning}] = program.errors
  end

  test "reports a fatal no-root when nothing can be the entry" do
    program = OpenUI.Parser.parse(fixture("entry/007-no-root-component-call"), library())
    assert program.root == nil
    assert [%OpenUI.Error{code: "no-root", severity: nil}] = program.errors
  end

  test "reports an enum mismatch on text cut inside a multibyte character" do
    program =
      OpenUI.Parser.parse(~s|root = Stack([Tag("x", "pur| <> <<195>> <> ~s|")])|, library())

    assert [%OpenUI.Error{code: "type-mismatch"}] = program.errors
  end

  test "flags a program cut inside a string as incomplete" do
    assert OpenUI.Parser.parse(~s|root = Stack([t])\nt = Text("a|, library()).incomplete
  end

  test "reports parse-failed for text with no statements and never raises on a broken library" do
    assert [%OpenUI.Error{code: "parse-failed"}] =
             OpenUI.Parser.parse("hello there", library()).errors

    assert [%OpenUI.Error{code: "parse-exception"}] =
             OpenUI.Parser.parse("root = Stack([])", :not_a_library).errors
  end

  test "returns an empty program, with no error, for a response that holds only comments" do
    assert OpenUI.Parser.parse("// thinking about the layout\n", library()) == %OpenUI.Program{}
  end

  test "builds a program from statements a host read one at a time" do
    statements = Enum.map(["root = Stack([t])", ~S|t = Text("Hi")|], &OpenUI.Parser.statement/1)
    program = OpenUI.Parser.build(statements, library())

    assert %Element{type: "Stack", props: %{"children" => [%Element{type: "Text"}]}} =
             program.root

    assert program.errors == []
  end

  test "reports a fatal no-root when the statement that calls the root component is dropped" do
    program = OpenUI.Parser.parse("page = Stack()", library())

    assert program.root == nil

    assert [
             %OpenUI.Error{code: "missing-required"},
             %OpenUI.Error{code: "no-root", severity: nil}
           ] = program.errors
  end

  test "reports only the dropped component when root names a statement that was dropped" do
    program = OpenUI.Parser.parse("root = page\npage = Stack()", library())

    assert program.root == nil
    assert errors(program) == [{"page", "missing-required", "/children"}]
  end

  test "renders a root that picks one of several pages by index" do
    program =
      OpenUI.Parser.parse(
        ~S"""
        $tab = 1
        root = [Stack([Text("Overview")]), Stack([Text("Details")])][$tab]
        """,
        library()
      )

    assert program.errors == []

    assert OpenUI.Canonical.result(program, library())["root"] == %{
             "type" => "Stack",
             "props" => %{"children" => [%{"type" => "Text", "props" => %{"text" => "Details"}}]}
           }
  end

  test "reports no-root without naming a component when the library has no root" do
    program = OpenUI.Parser.parse(~S|ticket = Ticket("Printer down")|, hand_written_library())

    assert program.root == nil
    assert messages(program) == ["No root statement"]
  end

  test "drops a component whose required prop has the wrong type" do
    program =
      OpenUI.Parser.parse(
        ~S|root = Stack([Metric("Revenue", "ten"), Metric("Tickets", 12)])|,
        library()
      )

    assert [%Element{type: "Metric", props: %{"label" => "Tickets"}}] = children(program)
    assert errors(program) == [{"root", "type-mismatch", "/value"}]
  end

  test "replaces a value that does not fit with the default of its prop" do
    program =
      OpenUI.Parser.parse(~S|root = Ticket("Printer down", "urgent")|, hand_written_library())

    assert program.root.props == %{"title" => "Printer down", "priority" => "low"}
    assert errors(program) == [{"root", "type-mismatch", "/priority"}]
  end

  test "names the type of a value that does not fit the way JavaScript does" do
    program =
      OpenUI.Parser.parse(
        ~S|root = Stack([Text(true), Text({label: "x"}), Text(["a"]), Tag("New", 1), Table([Col("Name", "Ana")])])|,
        library()
      )

    assert messages(program) == [
             ~s(field "/text" expects string but got boolean),
             ~s(field "/text" expects string but got object),
             ~s(field "/text" expects string but got array),
             ~s(field "/color" expects one of ["gray", "green", "red"] but got 1),
             ~s(field "/data" expects array but got string)
           ]
  end

  test "checks each field of an object prop and leaves the prop out when it does not fit" do
    program =
      OpenUI.Parser.parse(
        ~S"""
        root = Stack([open, waiting, closed, pending, late, reopened, escalated])
        open = Metric("Open", 12, {direction: "up", percent: 5})
        waiting = Metric("Waiting", 6, {direction: "up"})
        closed = Metric("Closed", 3, {direction: "sideways"})
        pending = Metric("Pending", 4, {direction: "down", percent: "ten"})
        late = Metric("Late", 2, {percent: 5})
        reopened = Metric("Reopened", 1, {direction: null})
        escalated = Metric("Escalated", 0, ["up"])
        """,
        OpenUI.Test.ExampleLibrary
      )

    assert Enum.map(children(program), & &1.props["trend"]) == [
             %{"direction" => "up", "percent" => 5},
             %{"direction" => "up"},
             nil,
             %{"direction" => "down"},
             nil,
             nil,
             nil
           ]

    assert errors(program) == [
             {"closed", "type-mismatch", "/trend/direction"},
             {"pending", "type-mismatch", "/trend/percent"},
             {"late", "missing-required", "/trend/direction"},
             {"reopened", "null-required", "/trend/direction"},
             {"escalated", "type-mismatch", "/trend"}
           ]
  end

  test "waits for a required field of an object prop while the text may still grow" do
    program =
      OpenUI.Parser.parse(
        ~S|root = Stack([Metric("Open", 12, {percent: 5|,
        OpenUI.Test.ExampleLibrary
      )

    assert program.incomplete
    assert program.errors == []
    assert [%Element{props: %{"trend" => %{"percent" => 5}}}] = children(program)
  end

  test "refuses a list in a component slot and a word in a boolean prop" do
    program =
      OpenUI.Parser.parse(
        ~S|root = Stack([Highlight([Card("Open")]), Highlight(Card("Late"), "yes"), Highlight(Card("New"), true)])|,
        OpenUI.Test.ExampleLibrary
      )

    assert Enum.map(children(program), & &1.props["enabled"]) == [nil, true]

    assert messages(program) == [
             ~s(field "/content" expects Card | Metric but got array),
             ~s(field "/enabled" expects boolean but got string)
           ]
  end

  test "keeps any value in a list whose items take any type" do
    program =
      OpenUI.Parser.parse(
        ~S|root = Stack([Table([Col("Owner", ["Ana", 3, true, null])])])|,
        OpenUI.Test.ExampleLibrary
      )

    assert [%Element{props: %{"columns" => [column]}}] = children(program)
    assert column.props["data"] == ["Ana", 3, true, nil]
    assert program.errors == []
  end

  test "accepts plain text in a prop that takes text or a component" do
    program = OpenUI.Parser.parse(~S|root = Ticket("Printer down")|, hand_written_library())

    assert program.root.props["title"] == "Printer down"
    assert program.errors == []
  end

  test "reports a required key that an object schema lists without describing" do
    program =
      OpenUI.Parser.parse(~S|root = Ticket("Printer down", "high", {})|, hand_written_library())

    assert program.root.props == %{"title" => "Printer down", "priority" => "high"}
    assert errors(program) == [{"root", "missing-required", "/meta/id"}]
  end

  test "leaves out an unknown component given as a single prop and reports it" do
    program = OpenUI.Parser.parse(~S|root = Stack([Card("Sales", Chart())])|, library())

    assert [%Element{type: "Card", props: %{"children" => nil}}] = children(program)
    assert errors(program) == [{"root", "unknown-component", ""}]
  end

  test "keeps an unknown component inside a computed expression and reports it" do
    program =
      OpenUI.Parser.parse(
        ~S|root = Stack([$compact ? Chart("Tickets") : Text("Tickets")])|,
        library()
      )

    assert [{:ternary, _condition, {:component, "Chart", _args}, _else}] = children(program)
    assert errors(program) == [{"root", "unknown-component", ""}]
  end

  test "reports @Query written inside a prop as inline-reserved" do
    program = OpenUI.Parser.parse(~S|root = Stack([Text(@Query("tickets", {}, {}))])|, library())

    assert children(program) == []

    assert Enum.map(program.errors, & &1.code) == ["inline-reserved", "null-required"]
  end

  test "inlines references in the value of an inline state assignment" do
    program =
      OpenUI.Parser.parse(
        ~S"""
        root = Stack([Input("q", "Search", $q = greeting)])
        greeting = "Hi"
        """,
        library()
      )

    assert [%Element{props: %{"value" => {:assign, "$q", {:string, "Hi"}}}}] = children(program)
    assert program.orphans == []
  end

  test "scopes the Each iterator only when it is a name" do
    program =
      OpenUI.Parser.parse(
        ~S"""
        root = Stack([Card("Named", @Each(tickets, ticket, Text(ticket))), Card("Numbered", @Each(tickets, 1, Text(row)))])
        tickets = ["Printer", "VPN"]
        """,
        library()
      )

    assert program.unresolved == ["row"]
  end

  test "turns a library action whose argument does not fit into a no-op" do
    program =
      OpenUI.Parser.parse(
        ~S|root = Stack([Button("Copy", @CopyToClipboard(42)), Button("Copy", @CopyToClipboard("T-42"))])|,
        library()
      )

    assert [%OpenUI.Error{code: "type-mismatch", path: "/text", hint: hint}] = program.errors
    assert hint == "Signature: CopyToClipboard(text*). * marks required"

    buttons = OpenUI.Canonical.result(program, library())["root"]["props"]["children"]

    assert Enum.map(buttons, & &1["props"]["action"]) == [
             %{"actions" => []},
             %{"actions" => [%{"action" => "CopyToClipboard", "args" => ["T-42"]}]}
           ]
  end

  test "checks the literal arguments of a library function like props" do
    program =
      OpenUI.Parser.parse(
        ~S"""
        root = Stack([checked, defaulted, empty])
        checked = Text(@Summary([3, "x", 5], {urgent: true, assignee: null, tags: ["vip", 7]}, "ten", "yes"))
        defaulted = Text(@Summary([1], {status: "pending"}))
        empty = Text(@Summary(null))
        """,
        TicketSummaryCatalog
      )

    assert Enum.map(children(program), & &1.props["text"]) == [
             {:call, "Summary",
              [
                {:array, [{:number, 3}, {:number, 5}]},
                {:object,
                 [
                   {"assignee", :null},
                   {"status", {:string, "open"}},
                   {"tags", {:array, [{:string, "vip"}]}},
                   {"urgent", {:boolean, true}}
                 ]},
                {:number, 10},
                :null
              ]},
             {:call, "Summary",
              [{:array, [{:number, 1}]}, {:object, [{"status", {:string, "open"}}]}]},
             :null
           ]

    assert errors(program) == [
             {"checked", "type-mismatch", "/ids/1"},
             {"checked", "type-mismatch", "/filter/tags/1"},
             {"checked", "type-mismatch", "/limit"},
             {"checked", "type-mismatch", "/verbose"},
             {"defaulted", "type-mismatch", "/filter/status"},
             {"empty", "null-required", "/ids"}
           ]
  end

  test "leaves the arguments of a library function that read state for the runtime" do
    call = ~S|@Summary([$first, "x"], {status: $status, urgent: "yes"})|
    program = OpenUI.Parser.parse("root = Stack([Text(#{call})])", TicketSummaryCatalog)

    assert [%Element{props: %{"text" => text}}] = children(program)
    assert text == Expression.parse(Lexer.tokenize(call))
    assert program.errors == []
  end
end
