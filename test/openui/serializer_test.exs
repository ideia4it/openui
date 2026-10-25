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
end
