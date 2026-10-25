defmodule OpenUI.Prompt do
  @moduledoc """
  Generates the system prompt that teaches a model a library (prompt.md,
  section 4). For the same library and options the prompt is byte-identical
  to the official `generateSystemPrompt`.

      OpenUI.Prompt.generate(MyApp.Library, tools: ["list_tickets"], edit_mode: true)

  Options:

    * `:tools`: tool names, or maps `%{name:, description:, input_schema:,
      output_schema:}`. Schemas may be JSON text, `OpenUI.JSON.Object` or
      maps; a plain map lists its properties in key order, so use one of the
      first two to keep the order you wrote.
    * `:tool_calls`: teaches `Query`, `Mutation` and `@Run`. Defaults to
      true when `:tools` is given.
    * `:bindings`: teaches `$variables`, `@Set` and `@Reset`. Defaults to
      `:tool_calls`.
    * `:builtin_functions`: lists the built-in functions even when the two
      options above are off.
    * `:edit_mode`, `:inline_mode`: teach edits by changed statements and
      prose with fenced code.
    * `:preamble`, `:examples`, `:tool_examples`, `:additional_rules`: text
      the host adds.
  """

  alias OpenUI.JSON
  alias OpenUI.JSON.Object
  alias OpenUI.Library
  alias OpenUI.Prompt.Text

  @separator " \u2014 "
  @restricted_slot ~r/[:|] @[A-Z]/

  @builtin_functions [
    {"Count(array: any[]) \u2192 number", "Returns array length"},
    {"First(array: any[]) \u2192 any", "Returns first element of array"},
    {"Last(array: any[]) \u2192 any", "Returns last element of array"},
    {"Sum(numbers: number[]) \u2192 number", "Sum of numeric array"},
    {"Avg(numbers: number[]) \u2192 number", "Average of numeric array"},
    {"Min(numbers: number[]) \u2192 number", "Minimum value in array"},
    {"Max(numbers: number[]) \u2192 number", "Maximum value in array"},
    {~s|Sort(array: any[], field: string, direction?: "asc" \| "desc") \u2192 any[]|,
     ~s|Sort array by field. Direction: "asc" (default) or "desc"|},
    {~s|Filter(array: any[], field: string, operator: "==" \| "!=" \| ">" \| "<" \| ">=" \| "<=" \| "contains", value: any) \u2192 any[]|,
     "Filter array by field value"},
    {"Round(number: number, decimals?: number) \u2192 number",
     "Round to N decimal places (default 0)"},
    {"Abs(number: number) \u2192 number", "Absolute value"},
    {"Floor(number: number) \u2192 number", "Round down to nearest integer"},
    {"Ceil(number: number) \u2192 number", "Round up to nearest integer"},
    {"Each(array: any[], varName: string, template: any)",
     "Evaluate template for each element. varName is the loop variable \u2014 use it ONLY inside the template expression (inline). Do NOT create a separate statement for the template."}
  ]

  @builtin_steps [
    {"Run", "Run(ref: Query | Mutation)",
     "Execute a Mutation or re-fetch a Query (ref must be a declared Query/Mutation)"},
    {"ToAssistant", "ToAssistant(message: string, context?: any)",
     ~s|Send a message to the assistant (for conversational buttons like "Tell me more", "Explain this"). The optional context is any value (object, array, string, number) passed to the assistant as hidden data, e.g. @ToAssistant("Show details", {orderId: 42})|},
    {"OpenUrl", "OpenUrl(url: string)", "Navigate to a URL"},
    {"Set", "Set(variable: $variable, value: any)", "Set a $variable to a specific value"},
    {"Reset", "Reset(variable: $variable)",
     ~s|Reset $variables to their declared defaults; pass several to reset each (e.g. @Reset($title, $priority) restores $title="" and $priority="medium")|}
  ]

  @doc "Generates the system prompt for a library."
  @spec generate(Library.t() | module(), keyword()) :: String.t()
  def generate(library, opts \\ []) do
    library = Library.resolve(library)
    tools = option(opts, :tools, [])
    tool_calls? = option(opts, :tool_calls, tools != [])
    bindings? = option(opts, :bindings, tool_calls?)

    flags = %{
      root: library.root || "Root",
      tool_calls?: tool_calls?,
      bindings?: bindings?,
      expressions?: tool_calls? or bindings?,
      action_expression?: Enum.any?(library.components, &action_slot?/1)
    }

    [
      [
        option(opts, :preamble, Text.preamble()),
        "",
        syntax_rules(flags),
        "",
        component_signatures(library, flags)
      ],
      functions_part(library, flags, option(opts, :builtin_functions, flags.expressions?)),
      tool_call_part(flags),
      actions_part(library, flags),
      filters_part(flags),
      workflow_part(flags),
      tools_part(tools),
      ["", streaming_rules(flags)],
      examples_part(option(opts, :examples, []) ++ option(opts, :tool_examples, [])),
      mode_part(option(opts, :edit_mode, false), &Text.edit_mode/0),
      mode_part(option(opts, :inline_mode, false), &Text.inline_mode/0),
      [important_rules(flags)],
      additional_rules_part(option(opts, :additional_rules, []))
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp tool_call_part(%{tool_calls?: true}), do: ["", Text.query(), "", Text.mutation()]
  defp tool_call_part(_flags), do: []

  defp filters_part(%{tool_calls?: true, bindings?: true}), do: ["", Text.interactive_filters()]
  defp filters_part(_flags), do: []

  defp workflow_part(%{tool_calls?: true}), do: ["", Text.tool_workflow()]
  defp workflow_part(_flags), do: []

  defp tools_part([]), do: []
  defp tools_part(tools), do: ["", tools_section(tools)]

  defp mode_part(true, text), do: ["", text.()]
  defp mode_part(_off, _text), do: []

  # Like JavaScript's `??`: a nil option takes the default.
  defp option(opts, key, default) do
    case Keyword.get(opts, key) do
      nil -> default
      value -> value
    end
  end

  defp action_slot?(component),
    do:
      String.contains?(component.signature, "ActionExpression") or
        Regex.match?(@restricted_slot, component.signature)

  defp line(signature, description) when description in [nil, ""], do: signature
  defp line(signature, description), do: signature <> @separator <> description

  defp function_line(signature, description), do: line("@" <> signature, description)

  defp syntax_rules(flags) do
    base = [
      "## Syntax Rules",
      "",
      "1. Each statement is on its own line: `identifier = Expression`",
      "2. `root` is the entry point \u2014 every program must define `root = #{flags.root}(...)`",
      ~s|3. Expressions are: strings ("..."), numbers, booleans (true/false), null, arrays ([...]), objects ({...}), or component calls TypeName(arg1, arg2, ...)|,
      "4. Use references for readability: define `name = ...` on one line, then use `name` later",
      "5. EVERY variable (except root) MUST be referenced by at least one other variable. Unreferenced variables are silently dropped and will NOT render. Always include defined variables in their parent's children/items array.",
      ~s|6. Arguments are POSITIONAL (order matters, not names). Write `SomeComp([children], "row", "l")` NOT `SomeComp([children], direction: "row", gap: "l")` \u2014 colon syntax is NOT supported and silently breaks|,
      "7. Optional arguments can be omitted from the end"
    ]

    bindings =
      if flags.bindings?,
        do: [
          "Declare mutable state with `$varName = defaultValue`. Components marked with `$binding` can read/write these. Undeclared $variables are auto-created with null default."
        ],
        else: []

    expressions =
      if flags.expressions?,
        do: [
          ~s|String concatenation: `"text" + $var + "more"`|,
          "Dot member access: `query.field` reads a field; on arrays it extracts that field from every element",
          "Index access: `arr[0]`, `data[index]`",
          "Arithmetic operators: +, -, *, /, % (work on numbers; + is string concat when either side is a string)",
          "Comparison: ==, !=, >, <, >=, <=",
          "Logical: &&, ||, ! (prefix)",
          "Ternary: `condition ? valueIfTrue : valueIfFalse`",
          "Parentheses for grouping: `(a + b) * c`"
        ],
        else: []

    numbered =
      (bindings ++ expressions)
      |> Enum.with_index(8)
      |> Enum.map(fn {rule, number} -> "#{number}. #{rule}" end)

    Enum.join(base ++ numbered ++ ["- Strings use double quotes with backslash escaping"], "\n")
  end

  defp component_signatures(library, flags) do
    header = [
      "## Component Signatures",
      "",
      "Arguments marked with ? are optional. Sub-components can be inline or referenced; prefer references for better streaming."
    ]

    actions =
      if flags.action_expression? do
        steps =
          Enum.map(enabled_steps(flags), &elem(&1, 0)) ++ Enum.map(library.actions, & &1.name)

        restricted? = Enum.any?(library.components, &Regex.match?(@restricted_slot, &1.signature))

        [
          "Props typed `ActionExpression` accept one @step, or Action([@steps...]) for several. See the Action section for available steps (#{Enum.map_join(steps, ", ", &("@" <> &1))})."
          | if(restricted?,
              do: ["Props typed like `@OpenUrl | @ToAssistant` accept only the steps listed."],
              else: []
            )
        ]
      else
        []
      end

    bindings =
      if flags.bindings? or
           Enum.any?(library.components, &String.contains?(&1.signature, "$binding")),
         do: ["Props marked `$binding<type>` accept a `$variable` reference for two-way binding."],
         else: []

    Enum.join(header ++ actions ++ bindings ++ component_lines(library), "\n")
  end

  defp component_lines(%Library{groups: []} = library),
    do: ["" | Enum.map(library.components, &line(&1.signature, &1.description))]

  defp component_lines(library) do
    by_name = Map.new(library.components, &{&1.name, &1})

    {lines, grouped} =
      Enum.reduce(library.groups, {[], MapSet.new()}, fn group, {lines, grouped} ->
        {members, grouped} = group_members(group, by_name, grouped)
        {lines ++ ["", "### #{group.name}"] ++ members ++ group.notes, grouped}
      end)

    ungrouped = Enum.reject(library.components, &MapSet.member?(grouped, &1.name))

    other =
      if ungrouped == [],
        do: [],
        else: ["", "### Other" | Enum.map(ungrouped, &line(&1.signature, &1.description))]

    lines ++ other
  end

  # A component listed in two groups shows only in the first.
  defp group_members(group, by_name, grouped) do
    {members, grouped} =
      group.components
      |> Enum.filter(&Map.has_key?(by_name, &1))
      |> Enum.reduce({[], grouped}, fn name, {members, grouped} ->
        if MapSet.member?(grouped, name),
          do: {members, grouped},
          else:
            {[line(by_name[name].signature, by_name[name].description) | members],
             MapSet.put(grouped, name)}
      end)

    {Enum.reverse(members), grouped}
  end

  defp functions_part(library, flags, builtins?) do
    custom = Enum.map(library.functions, &function_line(&1.signature, &1.description))

    cond do
      builtins? -> ["", builtin_functions_section(custom, flags.tool_calls?)]
      custom != [] -> ["", "## Built-in Functions\n\n" <> Enum.join(custom, "\n")]
      true -> []
    end
  end

  defp builtin_functions_section(custom, tool_calls?) do
    lines =
      Enum.map(@builtin_functions, fn {signature, description} ->
        function_line(signature, description)
      end) ++ custom

    subject = if tool_calls?, do: "Query results", else: "data"

    """
    ## Built-in Functions

    Data functions prefixed with `@` to distinguish from components. These are the ONLY functions available \u2014 do NOT invent new ones.
    Use @-prefixed built-in functions (@Count, @Sum, @Avg, @Min, @Max, @Round) on #{subject}. Do NOT hardcode computed values.

    #{Enum.join(lines, "\n")}

    Builtins compose \u2014 output of one is input to the next:
    `@Count(@Filter(data.rows, "field", "==", "val"))` for KPIs/chart values, `@Round(@Avg(data.rows.score), 1)`, `@Each(data.rows, "item", Comp(item.field))` for per-item rendering.
    Array pluck: `data.rows.field` extracts a field from every row \u2192 use with @Sum, @Avg, charts, tables.

    IMPORTANT @Each rule: The loop variable (e.g. "item") is ONLY available inside the @Each template expression. Always inline the template \u2014 do NOT extract it to a separate statement.
    CORRECT: `list = @Each(rows, "t", Comp(t.name))`
    WRONG: `item = Comp(t.name)` then `list = @Each(rows, "t", item)`, because t is undefined in item.
    """
    |> String.trim_trailing("\n")
  end

  # @Run needs tool calls; @Set and @Reset need bindings.
  defp enabled_steps(flags) do
    Enum.filter(@builtin_steps, fn
      {"Run", _signature, _description} -> flags.tool_calls?
      {name, _signature, _description} when name in ["Set", "Reset"] -> flags.bindings?
      _step -> true
    end)
  end

  defp actions_part(library, flags) do
    custom = Enum.map(library.actions, &("- " <> function_line(&1.signature, &1.description)))

    cond do
      flags.action_expression? ->
        ["", action_section(flags, custom)]

      custom != [] ->
        [
          "",
          "## Action \u2014 Button Behavior\n\nPass one step, or Action([...]) with several steps, as a button's action.\n\nAvailable steps:\n" <>
            Enum.join(custom, "\n")
        ]

      true ->
        []
    end
  end

  defp action_section(flags, custom) do
    steps =
      Enum.map(enabled_steps(flags), fn {_name, signature, description} ->
        "- " <> function_line(signature, description)
      end) ++ custom

    mutation_example =
      if flags.tool_calls?,
        do: [
          """
          Example \u2014 mutation + refresh + reset (PREFERRED pattern):
          ```
          $binding = "default"
          result = Mutation("tool_name", {field: $binding})
          data = Query("tool_name", {}, {rows: []})
          onSubmit = Action([@Run(result), @Run(data), @Reset($binding)])
          ```\
          """
        ],
        else: []

    navigation_example = """
    Example \u2014 simple nav:
    ```
    viewBtn = Button("View", @OpenUrl("https://example.com"))
    ```\
    """

    rules =
      [
        ~s|- An action can be assigned to a variable or inlined: Button("Go", onSubmit) and Button("Go", Action([...])) both work|
      ] ++
        if(flags.tool_calls?,
          do: [
            "- If a @Run(mutation) step fails, remaining steps are skipped (halt on failure)",
            "- @Run(queryRef) re-fetches the query (fire-and-forget, cannot fail)"
          ],
          else: []
        )

    """
    ## Action \u2014 Button Behavior

    An action wires a button click to operations. Pass one @-prefixed step bare, e.g. Button("Ask", @ToAssistant("Tell me more")). Put several steps in Action([...]), e.g. Button("Read", Action([@OpenUrl("https://example.com"), @ToAssistant("Summarize this page")])). Steps execute in order.
    Buttons without an action automatically send their label to the assistant (equivalent to @ToAssistant(label)).

    Available steps:
    #{Enum.join(steps, "\n")}

    #{Enum.join(mutation_example ++ [navigation_example], "\n\n")}

    #{Enum.join(rules, "\n")}\
    """
  end

  defp streaming_rules(flags) do
    first = "1. `root = #{flags.root}(...)` \u2014 UI shell appears immediately"

    steps =
      if flags.expressions? do
        middle =
          ["2. $variable declarations \u2014 state ready for bindings"] ++
            if(flags.tool_calls?,
              do: [
                "3. Query statements \u2014 defaults resolve immediately so components render with data"
              ],
              else: []
            )

        count = length(middle) + 1

        [first | middle] ++
          [
            "#{count + 1}. Component definitions \u2014 fill in with data already available",
            "#{count + 2}. Data values \u2014 leaf content last"
          ]
      else
        [
          first,
          "2. Component definitions \u2014 fill in as they stream",
          "3. Data values \u2014 leaf content last"
        ]
      end

    """
    ## Hoisting & Streaming (CRITICAL)

    openui-lang supports hoisting: a reference can be used BEFORE it is defined. The parser resolves all references after the full input is parsed.

    During streaming, the output is re-parsed on every chunk. Undefined references are temporarily unresolved and appear once their definitions stream in. This creates a progressive top-down reveal \u2014 structure first, then data fills in.

    **Recommended statement order for optimal streaming:**
    #{Enum.join(steps, "\n")}

    Always write the root = #{flags.root}(...) statement first so the UI shell appears immediately, even before child data has streamed in.\
    """
  end

  defp important_rules(flags) do
    verify =
      [
        "1. root = #{flags.root}(...) is the FIRST line (for optimal streaming).",
        "2. Every referenced name is defined. Every defined name (other than root) is reachable from root."
      ] ++
        if(flags.tool_calls?,
          do: ["3. Every Query result is referenced by at least one component."],
          else: []
        ) ++
        if(flags.bindings?,
          do: [
            "#{if flags.tool_calls?, do: "4", else: "3"}. Every $binding appears in at least one component or expression."
          ],
          else: []
        ) ++
        if(flags.tool_calls? and flags.bindings?,
          do: ["5. Every visible filter $binding appears in at least one Query args object."],
          else: []
        )

    """
    ## Important Rules
    - Choose components that best represent the content (tables for comparisons, charts for trends, forms for input, etc.)

    ## Final Verification
    Before finishing, walk your output and verify:
    #{Enum.join(verify, "\n")}\
    """
  end

  defp examples_part([]), do: []
  defp examples_part(examples), do: ["", "## Examples", "" | Enum.flat_map(examples, &[&1, ""])]

  defp additional_rules_part([]), do: []
  defp additional_rules_part(rules), do: ["" | Enum.map(rules, &("- " <> &1))]

  defp tools_section(tools) do
    {names, specs} = Enum.split_with(tools, &is_binary/1)
    specs = Enum.map(specs, &normalize_tool/1)
    with_output = Enum.filter(specs, & &1.output_schema)

    defaults =
      if with_output == [],
        do: [],
        else:
          [
            "",
            "### Default values for Query results",
            "",
            "Use these shapes as minimal Query defaults:"
          ] ++
            Enum.map(
              with_output,
              &"- #{&1.name}: `#{JSON.encode!(default_for(&1.output_schema))}`"
            )

    ([
       "## Available Tools",
       "",
       "Use these with Query() for read operations or Mutation() for write operations. The LLM decides which is appropriate based on the tool's purpose.",
       ""
     ] ++
       Enum.map(names, &("- " <> &1)) ++
       Enum.map(specs, &tool_signature/1) ++
       defaults ++
       [
         "",
         "CRITICAL: Use ONLY the tools listed above in Query() and Mutation() calls. Do NOT invent or guess tool names. If the user asks for functionality that doesn't match any available tool, use realistic mock data instead of fabricating a tool call."
       ])
    |> Enum.join("\n")
  end

  defp normalize_tool(tool) do
    %{
      name: Map.fetch!(tool, :name),
      description: Map.get(tool, :description),
      input_schema: schema_object(Map.get(tool, :input_schema)),
      output_schema: schema_object(Map.get(tool, :output_schema))
    }
  end

  defp schema_object(nil), do: nil
  defp schema_object(json) when is_binary(json), do: JSON.decode!(json)
  defp schema_object(%Object{} = object), do: object
  defp schema_object(map) when is_map(map), do: ordered(map)

  defp ordered(map) when is_map(map) and not is_struct(map),
    do:
      map
      |> Enum.sort()
      |> Enum.map(fn {key, value} -> {to_string(key), ordered(value)} end)
      |> JSON.object()

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(value), do: value

  defp tool_signature(tool) do
    args =
      case tool.input_schema do
        nil -> ""
        schema -> schema |> properties() |> Enum.map_join(", ", &field_type(&1, required(schema)))
      end

    returns = if tool.output_schema, do: " \u2192 " <> type_string(tool.output_schema), else: ""
    signature = "- #{tool.name}(#{args})#{returns}"
    if tool.description, do: signature <> "\n  " <> tool.description, else: signature
  end

  defp field_type({key, schema}, required),
    do: "#{key}#{if key in required, do: "", else: "?"}: #{type_string(schema)}"

  defp properties(schema) do
    case Object.get(schema, "properties") do
      %Object{pairs: pairs} -> pairs
      _none -> []
    end
  end

  defp required(schema), do: Object.get(schema, "required") || []

  defp type_string(schema) do
    case Object.get(schema, "type") do
      "string" -> string_type(Object.get(schema, "enum"))
      type when type in ["number", "integer"] -> "number"
      "boolean" -> "boolean"
      "array" -> array_type(Object.get(schema, "items"))
      "object" -> object_type(schema)
      _other -> "any"
    end
  end

  defp string_type(nil), do: "string"
  defp string_type(values), do: Enum.map_join(values, " | ", &~s("#{&1}"))

  defp array_type(%Object{} = items), do: type_string(items) <> "[]"
  defp array_type(_none), do: "any[]"

  defp object_type(schema) do
    case properties(schema) do
      [] -> "object"
      fields -> "{" <> Enum.map_join(fields, ", ", &field_type(&1, required(schema))) <> "}"
    end
  end

  defp default_for(schema) do
    case Object.get(schema, "type") do
      "string" ->
        ""

      type when type in ["number", "integer"] ->
        0

      "boolean" ->
        false

      "array" ->
        []

      "object" ->
        schema
        |> properties()
        |> Enum.map(fn {key, field} -> {key, default_for(field)} end)
        |> JSON.object()

      _other ->
        nil
    end
  end
end
