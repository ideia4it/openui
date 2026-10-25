defmodule OpenUI.LibraryTest do
  use ExUnit.Case, async: true

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
end
