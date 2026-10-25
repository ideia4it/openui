defmodule OpenUI.Runtime.EvaluatorTest do
  use ExUnit.Case, async: true

  defp render(source) do
    library = OpenUI.Conformance.library()
    OpenUI.Canonical.result(OpenUI.Parser.parse(source, library), library)["root"]
  end

  test "rounds like Math.round and filters with every operator" do
    root =
      render(~S"""
      root = Stack([Table([Col("r", [@Round(2.5), @Round(-2.5), @Round(3.14159, 2), @Avg([]), @Max([])]),
        Col("f", [@Count(@Filter(rows, "n", ">", 1)), @Count(@Filter(rows, "t", "contains", "b")),
                  @Count(@Filter(rows, "n", "~", 1)), @Count(@Filter(rows, "n", null, 2))])])])
      rows = [{n: 1, t: "ab"}, {n: 2, t: "cd"}, {n: 3, t: "bb"}]
      """)

    [table] = root["props"]["children"]

    assert Enum.map(table["props"]["columns"], & &1["props"]["data"]) ==
             [[3, -2, 3.14, 0, 0], [2, 2, 0, 1]]
  end

  test "binds the @Each element before deferring the action of each row" do
    root =
      render(~S"""
      root = Stack(@Each(rows, "r", Button(r.t, @Set($sel, r.id))))
      rows = [{id: 1, t: "a"}, {id: 2, t: "b"}]
      """)

    assert Enum.map(root["props"]["children"], &{&1["props"]["label"], &1["props"]["action"]}) ==
             [
               {"a", %{"actions" => [%{"action" => "Set", "args" => ["$sel", 1]}]}},
               {"b", %{"actions" => [%{"action" => "Set", "args" => ["$sel", 2]}]}}
             ]
  end

  test "turns a raising custom function into a runtime-error and a null value" do
    {:ok, library} =
      OpenUI.Library.from_spec(File.read!(Path.join(OpenUI.Conformance.root(), "library.json")),
        functions: %{"Upper" => fn _ -> raise "boom" end}
      )

    program =
      OpenUI.Parser.parse(~S|root = Stack([Text(@Upper("x") == null ? "null" : "x")])|, library)

    result = OpenUI.Canonical.result(program, library)
    assert hd(result["root"]["props"]["children"])["props"]["text"] == "null"
    assert [%{"code" => "runtime-error"}] = result["errors"]
  end
end
