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

  defmodule UndescribedCatalog do
    use OpenUI.Library, id: "undescribed", version: "1.0.0", root: "Stack"

    component "Stack", props: [children: [type: {:array, :component}, required: true]]
  end

  defmodule ActionWithoutButtonCatalog do
    use OpenUI.Library, id: "action-without-button", version: "1.0.0", root: "Stack"

    component "Stack",
      description: "A column",
      props: [children: [type: {:array, :component}, required: true]]

    action "Notify",
      description: "Tells the support team",
      params: [message: [type: :string, required: true]]
  end

  # The expected texts below were checked byte for byte against
  # generateSystemPrompt of @openuidev/lang-core 1.0.1.

  test "generates the default prompt when called without options" do
    assert OpenUI.Prompt.generate(OpenUI.Test.ExampleLibrary) ==
             File.read!("test/fixtures/goldens/example-default.prompt.txt")
  end

  test "lists a component without a description by its signature alone, with no function or action section" do
    assert OpenUI.Prompt.generate(UndescribedCatalog) =~
             "streaming.\n\nStack(children: any[])\n\n## Hoisting & Streaming (CRITICAL)"
  end

  test "teaches custom actions in a section of their own when no prop takes an action" do
    assert OpenUI.Prompt.generate(ActionWithoutButtonCatalog) =~
             """
             Stack(children: any[]) \u2014 A column

             ## Action \u2014 Button Behavior

             Pass one step, or Action([...]) with several steps, as a button's action.

             Available steps:
             - @Notify(message: string) \u2014 Tells the support team

             ## Hoisting\
             """
  end

  test "lists tools given only by name, with no default shapes for their results" do
    assert OpenUI.Prompt.generate(OpenUI.Test.ExampleLibrary, tools: ["listTickets"]) =~
             "\n\n- listTickets\n\nCRITICAL: Use ONLY the tools listed above"
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
