defmodule OpenUI.Library.DSLTest do
  use ExUnit.Case, async: true

  alias OpenUI.JSON.Object

  test "generates the same LibrarySpec as the official library for the same catalog" do
    golden = "test/fixtures/goldens/example.spec.json" |> File.read!() |> OpenUI.JSON.decode!()
    ours = OpenUI.Library.to_spec(OpenUI.Test.ExampleLibrary)

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
