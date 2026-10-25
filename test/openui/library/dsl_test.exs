defmodule OpenUI.Library.DSLTest do
  use ExUnit.Case, async: true

  alias OpenUI.JSON.Object

  test "generates the same LibrarySpec as the official library for the same catalog" do
    golden = "test/fixtures/goldens/example.spec.json" |> File.read!() |> OpenUI.JSON.decode!()
    ours = OpenUI.Library.to_spec(compile_example_library())

    assert comparable(ours) == comparable(golden)
    assert Enum.sort(property_orders(ours)) == Enum.sort(property_orders(golden))
  end

  test "refuses a catalog that breaks the definition rules at compile time" do
    assert_raise CompileError, ~r/Card: required prop title comes after an optional prop/, fn ->
      Code.compile_string(~S"""
      defmodule BadOrder do
        use OpenUI.Library, root: "Card"
        component "Card", description: "x", props: [subtitle: [type: :string], title: [type: :string, required: true]]
      end
      """)
    end

    assert_raise CompileError, ~r/component Count uses a reserved name/, fn ->
      Code.compile_string(~S"""
      defmodule BadName do
        use OpenUI.Library
        component "Count", description: "x", props: []
      end
      """)
    end

    assert_raise CompileError, ~r/group Charts lists Pie, which is not a component/, fn ->
      Code.compile_string(~S"""
      defmodule BadGroup do
        use OpenUI.Library
        component "Card", description: "x", props: []
        group "Charts", ["Pie"]
      end
      """)
    end

    assert_raise CompileError, ~r/action copy must start with an uppercase letter/, fn ->
      Code.compile_string(~S"""
      defmodule LowercaseAction do
        use OpenUI.Library
        action "copy", description: "x", params: []
      end
      """)
    end
  end

  test "refuses a prop without a type, or one that refers to a component or action it lacks" do
    assert_raise CompileError, ~r/Card.title has no type/, fn ->
      Code.compile_string(~S"""
      defmodule UntypedProp do
        use OpenUI.Library
        component "Card", description: "x", props: [title: [required: true]]
      end
      """)
    end

    assert_raise CompileError, ~r/Board.items refers to Tile, which is not a component/, fn ->
      Code.compile_string(~S"""
      defmodule MissingComponent do
        use OpenUI.Library
        component "Board", description: "x", props: [items: [type: {:array, {:ref, "Tile"}}]]
      end
      """)
    end

    assert_raise CompileError, ~r/Button.share refers to Print, which is not an action/, fn ->
      Code.compile_string(~S"""
      defmodule MissingAction do
        use OpenUI.Library
        component "Button", description: "x", props: [share: [type: {:actions, ["Print"]}]]
      end
      """)
    end
  end

  test "refuses a function whose impl is not a remote capture" do
    assert_raise CompileError, ~r"Percent: impl must be a remote capture like &Mod.fun/1", fn ->
      Code.compile_string(~S"""
      defmodule AnonymousImpl do
        use OpenUI.Library
        function "Percent", description: "x", params: [], returns: :string, impl: fn _args -> "0%" end
      end
      """)
    end
  end

  test "writes lists of unions and slots for a single action as the official library does" do
    [{board, _binary}] =
      Code.compile_string(~S"""
      defmodule Board do
        use OpenUI.Library, root: "Board"

        component "Board",
          description: "Cards and metrics",
          props: [
            items: [type: {:array, {:one_of, [{:ref, "Card"}, {:ref, "Metric"}]}}, required: true],
            shares: [type: {:array, {:actions, ["CopyToClipboard", "OpenUrl"]}}],
            links: [type: {:array, {:actions, ["OpenUrl"]}}],
            ask: [type: {:actions, ["ToAssistant"]}]
          ]

        component "Card", description: "A titled container", props: [title: [type: :string, required: true]]
        component "Metric", description: "A number", props: [value: [type: :number, required: true]]
        action "CopyToClipboard", description: "Copies text", params: [text: [type: :string, required: true]]
      end
      """)

    spec = board |> OpenUI.Library.to_spec() |> OpenUI.JSON.to_plain()
    board_props = spec["schema"]["$defs"]["Board"]["properties"]

    assert spec["components"]["Board"]["signature"] ==
             "Board(items: (Card | Metric)[], shares?: (@CopyToClipboard | @OpenUrl)[], links?: @OpenUrl[], ask?: @ToAssistant)"

    assert board_props["links"]["items"] == %{"$ref" => "#/$defs/OpenUrl"}
    assert board_props["ask"] == %{"$ref" => "#/$defs/ToAssistant"}

    assert spec["schema"]["$defs"]["ToAssistant"] == %{
             "type" => "object",
             "properties" => %{
               "type" => %{"type" => "string", "const" => "continue_conversation"},
               "context" => %{"type" => "string"}
             },
             "required" => ["type"],
             "additionalProperties" => false
           }
  end

  test "accepts a function without a return type, as the official library does" do
    [{greetings, _binary}] =
      Code.compile_string(~S"""
      defmodule Greetings do
        use OpenUI.Library, root: "Text"

        component "Text", description: "A run of text", props: [text: [type: :string, required: true]]

        function "Greet",
          description: "Says hello",
          params: [name: [type: :string, required: true]],
          impl: &__MODULE__.greet/1

        def greet(%{"name" => name}), do: "Hello, " <> name
      end
      """)

    spec = greetings |> OpenUI.Library.to_spec() |> OpenUI.JSON.to_plain()

    assert spec["functions"]["Greet"]["signature"] == "Greet(name: string)"
    refute Map.has_key?(spec["schema"]["functions"]["Greet"], "returns")
  end

  test "ships its formatter rules so a host's import_deps keeps the DSL without parens" do
    files = Mix.Project.config()[:package][:files]
    {formatter, _binding} = Code.eval_file(".formatter.exs")

    assert ".formatter.exs" in files

    assert Enum.sort(formatter[:export][:locals_without_parens]) ==
             Enum.sort(action: 2, component: 2, function: 2, group: 2, group: 3)
  end

  test "accepts a required prop with a default after optional ones" do
    assert [{BackCompat, _}] =
             Code.compile_string(~S"""
             defmodule BackCompat do
               use OpenUI.Library
               component "Card", description: "x",
                 props: [title: [type: :string], footer: [type: :string, required: true, default: ""]]
             end
             """)
  end

  # test/support compiles before cover starts, so the example catalog is
  # compiled again here, under another name, for cover to see the DSL build it.
  defp compile_example_library do
    {:defmodule, meta, [_name, body]} =
      "test/support/example_library.ex" |> File.read!() |> Code.string_to_quoted!()

    [{module, _binary}] =
      Code.compile_quoted({:defmodule, meta, [OpenUI.Library.DSLTest.ExampleLibrary, body]})

    module
  end

  defp comparable(spec) do
    plain = OpenUI.JSON.to_plain(spec)
    Map.update!(plain, "schema", &Map.delete(&1, "$schema"))
  end

  # The key order of every "properties" object, with its path: it is the
  # positional order of arguments. The order of the objects themselves (such
  # as entries of $defs) carries no meaning.
  defp property_orders(value, path \\ [])

  defp property_orders(%Object{pairs: pairs}, path) do
    Enum.flat_map(pairs, fn
      {"properties", %Object{} = properties} ->
        [
          {Enum.reverse(path), Object.keys(properties)}
          | property_orders(properties, ["properties" | path])
        ]

      {key, value} ->
        property_orders(value, [key | path])
    end)
  end

  defp property_orders(list, path) when is_list(list),
    do:
      list
      |> Enum.with_index()
      |> Enum.flat_map(fn {item, index} -> property_orders(item, [index | path]) end)

  defp property_orders(_value, _path), do: []
end
