defmodule OpenUI.Test.ExampleLibrary do
  @moduledoc false
  # Mirrors scripts/goldens/example-library.mjs; change both together.

  use OpenUI.Library, id: "example", version: "1.0.0", root: "Stack"

  alias OpenUI.Test.ExampleFunctions

  component "Stack",
    description: "Lays out children in a column or a row",
    props: [
      children: [type: {:array, :component}, required: true],
      direction: [type: {:enum, ["row", "column"]}]
    ]

  component "Card",
    description: "A titled container",
    props: [title: [type: :string, required: true], children: [type: {:array, :component}]]

  component "Text",
    description: "A run of text",
    props: [
      text: [type: :string, required: true],
      variant: [type: {:enum, ["body", "heading"]}, default: "body"]
    ]

  component "Metric",
    description: "A labeled number with an optional trend",
    props: [
      label: [type: :string, required: true],
      value: [type: :number, required: true],
      trend: [
        type:
          {:object,
           [direction: [type: {:enum, ["up", "down"]}, required: true], percent: [type: :number]]}
      ]
    ]

  component "LineChart",
    description: "Time series, daily or monthly",
    props: [
      labels: [type: {:array, :string}, required: true],
      series: [type: {:array, {:ref, "Series"}}, required: true]
    ]

  component "Series",
    description: "One line of a LineChart",
    props: [
      name: [type: :string, required: true],
      values: [type: {:array, :number}, required: true]
    ]

  component "Table",
    description: "A table built from columns",
    props: [columns: [type: {:array, {:ref, "Col"}}, required: true]]

  component "Col",
    description: "One table column: a header and its cell values",
    props: [label: [type: :string, required: true], data: [type: {:array, :any}]]

  component "Button",
    description: "A clickable button",
    props: [
      label: [type: :string, required: true],
      action: [type: :action],
      variant: [type: {:enum, ["primary", "secondary"]}],
      share: [type: {:actions, ["CopyToClipboard", "OpenUrl"]}]
    ]

  component "Form",
    description: "Groups its inputs under a form name",
    props: [
      name: [type: :string, required: true],
      children: [type: {:array, :component}, required: true]
    ]

  component "Input",
    description: "A text field",
    props: [
      name: [type: :string, required: true],
      placeholder: [type: :string],
      value: [type: {:binding, :string}],
      rules: [type: {:object, []}]
    ]

  component "Select",
    description: "A dropdown",
    props: [
      name: [type: :string, required: true],
      items: [type: {:array, {:ref, "SelectItem"}}, required: true],
      value: [type: {:binding, :string}]
    ]

  component "SelectItem",
    description: "One option of a Select",
    props: [value: [type: :string, required: true], label: [type: :string, required: true]]

  component "Highlight",
    description: "A card or a metric to call attention to",
    props: [
      content: [type: {:one_of, [{:ref, "Card"}, {:ref, "Metric"}]}, required: true],
      enabled: [type: :boolean]
    ]

  function "Percent",
    description: "Part over total as a percentage string",
    params: [part: [type: :number, required: true], total: [type: :number, required: true]],
    returns: :string,
    impl: &ExampleFunctions.percent/1

  action "CopyToClipboard",
    description: "Copies text to the clipboard",
    params: [text: [type: :string, required: true]]

  group "Layout", ["Stack", "Card"]
  group "Charts", ["LineChart", "Series"], notes: ["Prefer a chart over a table for series."]
  group "Forms", ["Form", "Input", "Select", "SelectItem", "Button"]
end
