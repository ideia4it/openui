defmodule OpenUI.Runtime.EvaluatorTest do
  use ExUnit.Case, async: true

  alias OpenUI.Runtime.{Context, Evaluator}

  # A LibrarySpec from another client, whose function declares no return type.
  @greetings_spec ~S"""
  {
    "id": "greetings",
    "version": "1.0.0",
    "root": "Stack",
    "schema": {
      "properties": {"Stack": {"$ref": "#/$defs/Stack"}, "Text": {"$ref": "#/$defs/Text"}},
      "$defs": {
        "Stack": {
          "type": "object",
          "properties": {"children": {"type": "array", "items": {"$ref": "#/$defs/Text"}}},
          "required": ["children"]
        },
        "Text": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}
      },
      "functions": {
        "Greet": {
          "description": "Greets a person by name",
          "params": {
            "type": "object",
            "properties": {
              "name": {"type": "string"},
              "greeting": {"type": "string", "default": "Hello"},
              "punctuation": {"type": "string"}
            },
            "required": ["name"]
          }
        }
      }
    }
  }
  """

  defp result(source, library \\ OpenUI.Conformance.library()),
    do: OpenUI.Canonical.result(OpenUI.Parser.parse(source, library), library)

  defp render(source, library \\ OpenUI.Conformance.library()),
    do: result(source, library)["root"]

  defp column_data(root) do
    [table] = root["props"]["children"]
    Enum.map(table["props"]["columns"], & &1["props"]["data"])
  end

  defp fixtures_library(functions) do
    {:ok, library} =
      OpenUI.Library.from_spec(File.read!(Path.join(OpenUI.Conformance.root(), "library.json")),
        functions: functions
      )

    library
  end

  test "rounds like Math.round and filters with every operator" do
    root =
      render(~S"""
      root = Stack([Table([Col("r", [@Round(2.5), @Round(-2.5), @Round(3.14159, 2), @Avg([]), @Max([])]),
        Col("f", [@Count(@Filter(rows, "n", ">", 1)), @Count(@Filter(rows, "t", "contains", "b")),
                  @Count(@Filter(rows, "n", "~", 1)), @Count(@Filter(rows, "n", null, 2)),
                  @Count(@Filter(rows, "n", "!=", 1))])])])
      rows = [{n: 1, t: "ab"}, {n: 2, t: "cd"}, {n: 3, t: "bb"}]
      """)

    assert column_data(root) == [[3, -2, 3.14, 0, 0], [2, 2, 0, 1, 2]]
  end

  test "aggregates arrays with First, Last, Sum, Avg, Min and Max and rounds with Abs, Floor and Ceil" do
    root =
      render(~S"""
      root = Stack([Table([
        Col("first and last", [@First(n), @First([]), @Last(n), @Last(null)]),
        Col("totals", [@Sum(n), @Sum(null), @Avg(n), @Min(n), @Min([]), @Max(n)]),
        Col("rounding", [@Abs(-2.5), @Floor(2.7), @Floor(-2.5), @Ceil(2.1)])])])
      n = [3, "1", true, 10]
      """)

    assert column_data(root) == [[3, nil, 10, nil], [15, 0, 3.75, 1, 0, 10], [2.5, 2, -3, 3]]
  end

  test "sorts stably, and the empty string as text rather than as the number 0" do
    root =
      render(~S"""
      root = Stack([Table([Col("by name", @Sort(rows, "name").id), Col("by n", @Sort(rows, "n").id),
        Col("with empty", @Sort(["10", "", "-5"], ""))])])
      rows = [{id: 1, name: "b", n: 2}, {id: 2, name: "a", n: 1}, {id: 3, name: "b", n: 1}]
      """)

    assert column_data(root) == [[2, 1, 3], [2, 3, 1], ["", "-5", "10"]]
  end

  test "filters by a dot path, reading null through a value that is not an object" do
    root =
      render(~S"""
      root = Stack([Table([Col("in Recife", @Filter(rows, "address.city", "==", "Recife").id),
        Col("no city", @Filter(rows, "address.city", "==", null).id)])])
      rows = [{id: 1, address: {city: "Recife"}}, {id: 2, address: "unknown"}, {id: 3}]
      """)

    assert column_data(root) == [[1], [2, 3]]
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

  test "binds the loop variables of nested @Each, an inner one shadowing an outer one of the same name" do
    groups = ~S|groups = [{name: "a", items: ["x", "y"]}, {name: "b", items: ["z"]}]|

    nested =
      render(
        ~s|root = Stack(@Each(groups, "g", Card(g.name, @Each(g.items, "i", Text(g.name + i)))))\n| <>
          groups
      )

    shadowed =
      render(
        ~s|root = Stack(@Each(groups, "x", Card(x.name, @Each(x.items, "x", Text(x)))))\n| <>
          groups
      )

    card_texts = fn root ->
      for card <- root["props"]["children"],
          do: {card["props"]["title"], Enum.map(card["props"]["children"], & &1["props"]["text"])}
    end

    assert card_texts.(nested) == [{"a", ["ax", "ay"]}, {"b", ["bz"]}]
    assert card_texts.(shadowed) == [{"a", ["x", "y"]}, {"b", ["z"]}]
  end

  test "keeps the outer loop variable in an action of a nested @Each" do
    root =
      render(~S"""
      root = Stack(@Each(groups, "g", Card(g.name, @Each(g.items, "i", Button(i, @Set($picked, g.name))))))
      groups = [{name: "a", items: ["x", "y"]}, {name: "b", items: ["z"]}]
      """)

    actions =
      for card <- root["props"]["children"], button <- card["props"]["children"] do
        [%{"args" => ["$picked", group]}] = button["props"]["action"]["actions"]
        {button["props"]["label"], group}
      end

    assert actions == [{"x", "a"}, {"y", "a"}, {"z", "b"}]
  end

  test "reads a bare name as the @Each loop variable" do
    root =
      render(~S"""
      root = Stack([Table([Col("tens", @Each(nums, n, n * 10))])])
      nums = [1, 2]
      """)

    assert column_data(root) == [[10, 20]]
  end

  test "renders an empty list for an @Each without an array, a template or a loop variable name" do
    root =
      render(~S"""
      root = Stack([Table([Col("each", [@Each(nothing, "n", n), @Each(nums, "n"), @Each(nums, 1, 2)])])])
      nums = [1, 2]
      nothing = null
      """)

    assert column_data(root) == [[[], [], []]]
  end

  test "reads null for a field or an index that does not exist" do
    root =
      render(~S"""
      root = Stack([Table([Col("reads", [count.x, pairs.0, pairs.first, nums.x, nothing[0], nums[-1], nums[1.5], count[0]])])])
      count = 5
      pairs = [[1, 2], [3, 4]]
      nums = [1, 2]
      nothing = null
      """)

    assert column_data(root) == [[nil, [1, 3], [nil, nil], [nil, nil], nil, nil, nil, nil]]
  end

  test "leaves an unknown component or an unresolved reference out of a computed array and renders null for it elsewhere" do
    result =
      result(~S"""
      $on = true
      root = Stack([Card("list", $on ? [Text("a"), Bogus("b"), missing, Text("c")] : []), $on ? Bogus("d") : Text("e")])
      """)

    [card, unknown] = result["root"]["props"]["children"]
    assert Enum.map(card["props"]["children"], & &1["props"]["text"]) == ["a", "c"]
    assert unknown == nil
    assert [%{"code" => "unknown-component"}, %{"code" => "unknown-component"}] = result["errors"]
  end

  test "evaluates a Query inline in a computed expression to null, with or without the @" do
    root =
      render(~S"""
      $on = true
      root = Stack([Table([Col("inline", [$on ? Query("list", {}) : 1, $on ? @Query("list", {}) : 1])])])
      """)

    assert column_data(root) == [[nil, nil]]
  end

  test "renders a $variable declared with a component where it is read" do
    root =
      render(~S"""
      $details = Card("Details", [Text("Open from 9 to 18")])
      root = Stack([$details])
      """)

    assert [%{"type" => "Card", "props" => %{"title" => "Details", "children" => [text]}}] =
             root["props"]["children"]

    assert text["props"]["text"] == "Open from 9 to 18"
  end

  test "makes an action call with nothing to act on a plan that does nothing" do
    root =
      render(~S"""
      root = Stack([Button("run", @Run(rows)), Button("set", @Set(rows, 1)), Button("not a list", Action("x")),
        Button("empty", Action()), Button("reset", @Reset(rows))])
      rows = [1]
      """)

    assert Enum.map(root["props"]["children"], & &1["props"]["action"]) ==
             List.duplicate(%{"actions" => []}, 5)
  end

  test "sends empty text for a null message or URL" do
    root =
      render(~S"""
      root = Stack([Button("ask", @ToAssistant($question)), Button("open", @OpenUrl($link))])
      """)

    assert Enum.map(root["props"]["children"], & &1["props"]["action"]) == [
             %{"actions" => [%{"action" => "ToAssistant", "args" => [""]}]},
             %{"actions" => [%{"action" => "OpenUrl", "args" => [""]}]}
           ]
  end

  test "measures text cut inside a multibyte character without raising" do
    ctx = %Context{library: OpenUI.Conformance.library()}
    assert Evaluator.evaluate({:member, {:literal, "a" <> <<195>>}, "length"}, ctx) == 2
  end

  test "turns a raising custom function into a runtime-error and a null value" do
    library = fixtures_library(%{"Upper" => fn _ -> raise "boom" end})

    result = result(~S|root = Stack([Text(@Upper("x") == null ? "null" : "x")])|, library)

    assert hd(result["root"]["props"]["children"])["props"]["text"] == "null"
    assert [%{"code" => "runtime-error"}] = result["errors"]
  end

  test "turns a custom function that throws or exits into a runtime-error and a null value" do
    library =
      fixtures_library(%{
        "Upper" => fn
          %{"text" => "throw"} -> throw(:no_answer)
          %{"text" => "exit"} -> exit(:shutdown)
        end
      })

    result =
      result(
        ~S{root = Stack([Text(@Upper("throw") || "null"), Text(@Upper("exit") || "null")])},
        library
      )

    assert Enum.map(result["root"]["props"]["children"], & &1["props"]["text"]) == [
             "null",
             "null"
           ]

    assert [%{"code" => "runtime-error"}, %{"code" => "runtime-error"}] = result["errors"]
  end

  test "turns a custom function without an implementation into a runtime-error and a null value" do
    result = result(~S{root = Stack([Text(@Upper("x") || "null")])}, fixtures_library(%{}))

    assert hd(result["root"]["props"]["children"])["props"]["text"] == "null"

    assert [%{"code" => "runtime-error", "component" => "Text", "message" => message}] =
             result["errorObjects"]

    assert message =~ "no implementation"
  end

  test "rejects a custom function result of the wrong type with a runtime-error" do
    library = fixtures_library(%{"Upper" => fn _ -> 42 end})

    result = result(~S{root = Stack([Text(@Upper("x") || "null")])}, library)

    assert hd(result["root"]["props"]["children"])["props"]["text"] == "null"
    assert [%{"code" => "runtime-error"}] = result["errors"]
  end

  test "rejects a custom function argument of the wrong type without running the function" do
    test_process = self()
    library = fixtures_library(%{"Upper" => fn args -> send(test_process, {:upper, args}) end})

    result =
      result(
        ~S"""
        $count = 5
        root = Stack([Text(@Upper($count) || "null")])
        """,
        library
      )

    assert hd(result["root"]["props"]["children"])["props"]["text"] == "null"
    assert [%{"code" => "runtime-error"}] = result["errors"]
    refute_received {:upper, _args}
  end

  test "reports a function that fails in the root expression without naming a prop" do
    result =
      result(~S"""
      $count = 5
      root = @Upper($count) == "5" ? Stack([Text("five")]) : Stack([Text("other")])
      """)

    assert hd(result["root"]["props"]["children"])["props"]["text"] == "other"
    assert [%{"code" => "runtime-error", "source" => "runtime"} = error] = result["errorObjects"]
    refute Map.has_key?(error, "component")
    refute Map.has_key?(error, "statementId")
  end

  test "fills optional arguments of a custom function from their defaults and keeps a result of no declared type" do
    greet = fn params ->
      "#{params["greeting"]}, #{params["name"]}#{params["punctuation"]}"
    end

    {:ok, library} = OpenUI.Library.from_spec(@greetings_spec, functions: %{"Greet" => greet})

    root =
      render(
        ~S"""
        $count = 5
        root = Stack([Text(@Greet("Ana")), Text(@Greet("Bia", $count)), Text(@Greet("Caio", "Hi", $count)),
          Text(@Greet("Duda", null, "!"))])
        """,
        library
      )

    assert Enum.map(root["props"]["children"], & &1["props"]["text"]) ==
             ["Hello, Ana", "Hello, Bia", "Hi, Caio", "Hello, Duda!"]
  end

  test "makes a library action with a null or wrong-type argument a plan that does nothing" do
    result =
      result(~S"""
      $count = 5
      root = Stack([Button("unset", @CopyToClipboard($text)), Button("number", @CopyToClipboard($count))])
      """)

    assert Enum.map(result["root"]["props"]["children"], & &1["props"]["action"]) ==
             List.duplicate(%{"actions" => []}, 2)

    assert [%{"code" => "runtime-error", "component" => "Button"}] = result["errorObjects"]
  end
end
