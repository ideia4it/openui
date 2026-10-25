defmodule OpenUI.LibraryTest do
  use ExUnit.Case, async: true

  alias OpenUI.Library.Rules

  setup do
    {:ok, library} =
      OpenUI.Library.from_spec(File.read!(Path.join(OpenUI.Conformance.root(), "library.json")))

    %{library: library}
  end

  test "reads the fixtures library keeping positional order, kinds and bindable props", %{
    library: library
  } do
    assert {library.id, library.version, library.root} == {"fixtures", "1.0.0", "Stack"}

    assert Enum.map(library.components, & &1.name) ==
             ~w(Stack Card Text Tag Metric Button Form Input Select SelectItem Table Col)

    button = OpenUI.Library.component(library, "Button")

    assert Enum.map(button.props, &{&1.name, &1.required?, &1.kind}) == [
             {"label", true, :value},
             {"action", false, :action},
             {"variant", false, :value},
             {"share", false, :action}
           ]

    assert Enum.map(OpenUI.Library.component(library, "Input").props, & &1.bindable?) ==
             [false, false, true, false]

    assert hd(OpenUI.Library.component(library, "Stack").props).kind == :components
    assert [%{name: "Upper", params: [%{name: "text", required?: true}]}] = library.functions
    assert [%{name: "CopyToClipboard"}] = library.actions
  end

  test "writes back the spec it read", %{library: library} do
    original = File.read!(Path.join(OpenUI.Conformance.root(), "library.json"))

    assert OpenUI.JSON.encode!(OpenUI.Library.to_spec(library)) ==
             OpenUI.JSON.encode!(OpenUI.JSON.decode!(original))
  end

  test "refuses a spec that breaks the library rules" do
    spec = ~S"""
    {"root": "Missing",
     "schema": {"properties": {"Query": {"$ref": "#/$defs/Query"}},
                "$defs": {"Query": {"type": "object",
                                    "properties": {"a": {"type": "string"}, "b": {"type": "string"}},
                                    "required": ["b"]}}},
     "components": {"Query": {"signature": "Query(a?: string, b: string)", "description": ""}}}
    """

    assert {:error, problems} = OpenUI.Library.from_spec(spec)
    assert "component Query uses a reserved name" in problems
    assert "Query: required prop b comes after an optional prop" in problems
    assert "root Missing is not a component" in problems
  end

  test "refuses text that is not a LibrarySpec object" do
    assert OpenUI.Library.from_spec(~S|["Stack"]|) ==
             {:error, ["a LibrarySpec must be a JSON object"]}

    assert {:error, ["invalid JSON: " <> _reason]} = OpenUI.Library.from_spec(~S|{"root": |)
  end

  test "refuses every name the language reserves, built-ins included" do
    reserved = Rules.reserved_names()

    named_by_the_spec =
      ["Query", "Mutation", "Action" | OpenUI.Builtins.functions() ++ OpenUI.Builtins.steps()]

    assert named_by_the_spec -- reserved == []

    for name <- reserved do
      spec = ~s"""
      {"schema": {"properties": {"#{name}": {"$ref": "#/$defs/#{name}"}},
                  "$defs": {"#{name}": {"type": "object", "properties": {}}}}}
      """

      assert OpenUI.Library.from_spec(spec) ==
               {:error, ["component #{name} uses a reserved name"]}
    end
  end

  test "reads a prop that refers to a schema outside the spec as a plain value" do
    spec = ~S"""
    {"schema": {"properties": {"Price": {"$ref": "#/$defs/Price"}},
                "$defs": {"Price": {"type": "object",
                                    "properties": {"amount": {"$ref": "https://example.com/money.json"}}}}}}
    """

    {:ok, library} = OpenUI.Library.from_spec(spec)

    assert [%{name: "amount", kind: :value}] = OpenUI.Library.component(library, "Price").props
  end

  test "shows only its id, version and root when inspected", %{library: library} do
    assert inspect(library) ==
             ~s(#OpenUI.Library<id: "fixtures", version: "1.0.0", root: "Stack", ...>)
  end
end
