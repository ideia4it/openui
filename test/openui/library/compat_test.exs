defmodule OpenUI.Library.CompatTest do
  use ExUnit.Case, async: true

  alias OpenUI.JSON
  alias OpenUI.Library.Compat

  test "flags removed, reordered and new required props without a default" do
    old = spec(%{"Button" => [{"label", true}, {"action", false}, {"variant", false}]})
    new = spec(%{"Button" => [{"variant", false}, {"label", true}, {"size", true}]})

    assert Enum.sort(Compat.check(old, new)) == [
             "Button: new required prop size needs a default",
             "Button: prop action was removed",
             "Button: prop label moved from position 1 to 2",
             "Button: prop variant moved from position 3 to 1"
           ]
  end

  test "accepts props appended at the end, required ones with a default" do
    old = spec(%{"Card" => [{"title", true}]})
    new = spec(%{"Card" => [{"title", true}, {"subtitle", false}, {"footer", {true, ""}}]})
    assert Compat.check(old, new) == []
  end

  test "leaves out a component the new version drops, since the rules only cover props" do
    old = spec(%{"Card" => [{"title", true}], "Badge" => [{"label", true}]})
    new = spec(%{"Card" => [{"title", true}]})
    assert Compat.check(old, new) == []
  end

  test "finds nothing to report between a library and itself, actions included" do
    spec = OpenUI.Library.to_spec(OpenUI.Test.ExampleLibrary)
    reread = spec |> JSON.encode!(pretty: true) |> JSON.decode!()
    assert Compat.check(reread, spec) == []
  end

  defp spec(components) do
    defs =
      for {name, props} <- components do
        properties = for {prop, required} <- props, do: {prop, prop_schema(required)}
        required = for {prop, required} <- props, required != false, do: prop

        {name,
         JSON.object([
           {"type", "object"},
           {"properties", JSON.object(properties)},
           {"required", required}
         ])}
      end

    properties =
      for {name, _props} <- components,
          do: {name, JSON.object([{"$ref", "#/$defs/" <> name}])}

    JSON.object([
      {"schema",
       JSON.object([
         {"properties", JSON.object(properties)},
         {"$defs", JSON.object(defs)}
       ])}
    ])
  end

  defp prop_schema({true, default}),
    do: JSON.object([{"default", default}, {"type", "string"}])

  defp prop_schema(_required), do: JSON.object([{"type", "string"}])
end
