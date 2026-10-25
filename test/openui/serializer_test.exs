defmodule OpenUI.SerializerTest do
  use ExUnit.Case, async: true

  alias OpenUI.Runtime.{Context, Evaluator}

  defp tree(source, library) do
    {tree, []} =
      Evaluator.evaluate_root(OpenUI.Parser.parse(source, library), %Context{library: library})

    tree
  end

  test "writes the entry first, named components before their parents and host state last" do
    library = OpenUI.Conformance.library()

    tree =
      tree(
        ~s|root = Stack([t, Card("C", [Text("x", "body")])], "column")\nt = Tag("new", "green")|,
        library
      )

    assert OpenUI.Serializer.to_source(tree, library, state: %{"$tab" => "a"}) ==
             ~s|root = Stack([t, Card("C", [Text("x", "body")])], "column")\nt = Tag("new", "green")\n$tab = "a"|
  end

  test "writes text cut inside a multibyte character without raising" do
    library = OpenUI.Conformance.library()
    tree = tree("root = Stack([Text(\"caf" <> <<195>> <> "\")])", library)
    assert OpenUI.Serializer.to_source(tree, library) =~ "Text("
  end

  test "fills holes with null, trims trailing optional nulls and keeps grouping" do
    library = OpenUI.Conformance.library()

    source =
      ~S|root = Stack([Button("Go", null, null, @OpenUrl("https://x.y")), Text("t", null)])|

    program = OpenUI.Parser.parse(source, library)
    written = OpenUI.Serializer.to_source(tree(source, library), library, state: %{})

    assert written =~ ~S|Button("Go", null, null, |
    assert written =~ ~S|Text("t")|

    assert OpenUI.Canonical.result(OpenUI.Parser.parse(written, library), library)["root"] ==
             OpenUI.Canonical.result(program, library)["root"]

    assert OpenUI.Serializer.expression(
             {:binary, "-", {:ref, "a"}, {:binary, "-", {:ref, "b"}, {:ref, "c"}}}
           ) ==
             "a - (b - c)"

    assert OpenUI.Serializer.expression({:unary, "-", {:binary, "+", {:ref, "a"}, {:ref, "b"}}}) ==
             "-(a + b)"
  end

  test "writes a component that an @Each item hands to @Set, in its catalog order" do
    library = OpenUI.Library.resolve(OpenUI.Test.ExampleLibrary)

    source =
      ~s|root = Stack(@Each([Card("Billing"), Card("Shipping")], "c", Button("Show", @Set($panel, c))))|

    assert OpenUI.Serializer.to_source(tree(source, library), library) ==
             ~s|root = Stack([Button("Show", @Set($panel, Card("Billing"))), Button("Show", @Set($panel, Card("Shipping")))])|
  end

  test "writes back numbers, booleans, objects, bindings and each kind of action step as written" do
    library = OpenUI.Library.resolve(OpenUI.Test.ExampleLibrary)

    source = """
    root = Stack([m, h, i, ask, save])
    m = Metric("Open", 12, {direction: "up", percent: 4.5})
    h = Highlight(Card("Top"), true)
    i = Input("q", "Search", $q)
    ask = Button("Ask", @ToAssistant("Tell me more"))
    save = Button("Save", Action([@Set($q, ""), @Reset($q), @ToAssistant("Saved", {id: 7})]), "primary", @CopyToClipboard("abc"))\
    """

    assert OpenUI.Serializer.to_source(tree(source, library), library) == source
  end

  test "writes the actions of an @Each over query rows with each row in place of the loop variable" do
    library = OpenUI.Library.resolve(OpenUI.Test.ExampleLibrary)

    source = """
    root = Stack(@Each(tickets.rows, "t", Button(t.title, Action([@Set($picked, t.id), @Set($rows, tickets.rows), @Run(tickets)]))))
    tickets = Query("list_tickets", {}, {rows: [{id: 1, title: "Printer"}]})
    """

    program = OpenUI.Parser.parse(source, library)

    assert OpenUI.Serializer.to_source(OpenUI.Canonical.tree(program, library), library) ==
             ~s|root = Stack([Button("Printer", Action([@Set($picked, {id: 1, title: "Printer"}.id), @Set($rows, tickets.rows), @Run(tickets)]))])|
  end

  test "writes back every expression a statement can hold, with only the parentheses it needs" do
    for expression <- [
          ~s|"Total: " + 3|,
          "true",
          "null",
          ~s|[1, "a"]|,
          "{a: 1, b: $x}",
          "$on ? 1 : 2",
          ~s|($on ? "Open" : "Closed") + ": " + $count|,
          "-$a * $b",
          "!$done && $ready",
          "q.rows[0].title",
          ~s|Input("q", null, $v = "")|,
          "Action([@Set($x, 1), @Reset($x)])",
          "@Count(rows)"
        ] do
      %OpenUI.Statement{ast: ast} = OpenUI.Parser.statement("x = " <> expression)
      assert OpenUI.Serializer.expression(ast) == expression
    end
  end

  test "writes null for a component the catalog lacks that a prop picks from a state list" do
    library = OpenUI.Library.resolve(OpenUI.Test.ExampleLibrary)
    source = ~s|root = Stack([Highlight($featured[0])])\n$featured = [Badge("new")]|
    program = OpenUI.Parser.parse(source, library)

    assert OpenUI.Serializer.to_source(OpenUI.Canonical.tree(program, library), library) ==
             "root = Stack([Highlight(null)])"
  end
end
