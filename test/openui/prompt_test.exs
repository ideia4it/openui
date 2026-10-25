defmodule OpenUI.PromptTest do
  use ExUnit.Case, async: true

  alias OpenUI.JSON.Object

  @external_resource "test/fixtures/goldens/cases.json"
  cases = "test/fixtures/goldens/cases.json" |> File.read!() |> OpenUI.JSON.decode!()

  for golden_case <- cases do
    @golden_case golden_case
    test "matches the official prompt for #{Object.get(golden_case, "name")}" do
      name = Object.get(@golden_case, "name")
      expected = File.read!("test/fixtures/goldens/#{name}.prompt.txt")

      assert OpenUI.Prompt.generate(library_for(@golden_case), options_for(@golden_case)) ==
               expected
    end
  end

  defp library_for(golden_case) do
    case Object.get(golden_case, "library") do
      "fixtures" -> OpenUI.Conformance.library()
      "example" -> OpenUI.Test.ExampleLibrary
    end
  end

  @option_names %{
    "tools" => :tools,
    "toolCalls" => :tool_calls,
    "bindings" => :bindings,
    "builtinFunctions" => :builtin_functions,
    "editMode" => :edit_mode,
    "inlineMode" => :inline_mode,
    "preamble" => :preamble,
    "examples" => :examples,
    "toolExamples" => :tool_examples,
    "additionalRules" => :additional_rules
  }

  defp options_for(golden_case) do
    for {key, value} <- Object.get(golden_case, "options").pairs do
      option = Map.fetch!(@option_names, key)
      {option, if(option == :tools, do: Enum.map(value, &tool/1), else: value)}
    end
  end

  defp tool(name) when is_binary(name), do: name

  defp tool(%Object{} = spec) do
    %{
      name: Object.get(spec, "name"),
      description: Object.get(spec, "description"),
      input_schema: Object.get(spec, "inputSchema"),
      output_schema: Object.get(spec, "outputSchema"),
      annotations: annotations(Object.get(spec, "annotations"))
    }
  end

  defp annotations(nil), do: nil

  defp annotations(%Object{} = annotations) do
    %{
      read_only_hint: Object.get(annotations, "readOnlyHint"),
      destructive_hint: Object.get(annotations, "destructiveHint")
    }
  end
end
