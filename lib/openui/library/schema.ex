defmodule OpenUI.Library.Schema do
  @moduledoc false
  # Turns the definitions of `use OpenUI.Library` into a LibrarySpec: the JSON
  # Schema of every component, function and action, and the prompt signature
  # of each, in the shapes the official library produces for the same catalog
  # (prompt.md, sections 2 and 5.1).
  #
  # Prop types:
  #
  #   :string | :number | :boolean | :any
  #   {:enum, ["a", "b"]}          {:array, type}
  #   {:object, [field: opts]}     {:ref, "Component"}
  #   {:one_of, [type]}            :component (any component of the library)
  #   :action                      {:actions, ["CopyToClipboard", "OpenUrl"]}
  #   {:binding, type}

  alias OpenUI.JSON

  @json_schema_draft "https://json-schema.org/draft/2020-12/schema"
  @builtin_action_refs ["OpenUrl", "ToAssistant"]

  @doc false
  def build(options, components, functions, actions, groups) do
    names = %{
      components: Enum.map(components, &elem(&1, 0)),
      actions: Enum.map(actions, &elem(&1, 0))
    }

    case Enum.flat_map(components ++ functions ++ actions, &type_problems(&1, names)) do
      [] ->
        {:ok, spec(options, components, functions, actions, groups, names),
         implementations(functions)}

      problems ->
        {:error, problems}
    end
  end

  defp spec(options, components, functions, actions, groups, names) do
    [
      {"root", Keyword.get(options, :root)},
      {"components", JSON.object(Enum.map(components, &component_prompt(&1, names)))},
      {"componentGroups", if(groups != [], do: Enum.map(groups, &group/1))},
      {"functions",
       if(functions != [], do: JSON.object(Enum.map(functions, &callable_prompt(&1, names))))},
      {"actions",
       if(actions != [], do: JSON.object(Enum.map(actions, &callable_prompt(&1, names))))},
      {"schema", schema(components, functions, actions, names)},
      {"id", Keyword.get(options, :id)},
      {"version", Keyword.get(options, :version)}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> JSON.object()
  end

  defp implementations(functions),
    do: Map.new(functions, fn {name, opts} -> {name, Keyword.fetch!(opts, :impl)} end)

  defp component_prompt({name, opts}, names) do
    {name,
     JSON.object([
       {"signature", signature(name, Keyword.get(opts, :props, []), nil, names)},
       {"description", Keyword.get(opts, :description, "")}
     ])}
  end

  defp callable_prompt({name, opts}, names) do
    {name,
     JSON.object([
       {"signature",
        signature(name, Keyword.get(opts, :params, []), Keyword.get(opts, :returns), names)},
       {"description", Keyword.get(opts, :description, "")}
     ])}
  end

  defp group({name, components, opts}) do
    notes = Keyword.get(opts, :notes, [])
    pairs = [{"name", name}, {"components", components}]
    JSON.object(if notes == [], do: pairs, else: pairs ++ [{"notes", notes}])
  end

  defp schema(components, functions, actions, names) do
    action_defs = action_defs(components, actions, names)

    pairs = [
      {"$schema", @json_schema_draft},
      {"type", "object"},
      {"properties", JSON.object(Enum.map(names.components, &{&1, ref(&1)}))},
      {"required", names.components},
      {"additionalProperties", false},
      {"$defs", JSON.object(Enum.map(components, &component_def(&1, names)) ++ action_defs)}
    ]

    pairs =
      if functions == [], do: pairs, else: pairs ++ [{"functions", calls(functions, names, true)}]

    pairs =
      if actions == [], do: pairs, else: pairs ++ [{"actions", calls(actions, names, false)}]

    JSON.object(pairs)
  end

  defp component_def({name, opts}, names) do
    object = object_schema(Keyword.get(opts, :props, []), names)
    {name, JSON.object(object.pairs ++ [{"description", Keyword.get(opts, :description, "")}])}
  end

  defp calls(definitions, names, returns?) do
    definitions
    |> Enum.map(fn {name, opts} ->
      pairs = [
        {"description", Keyword.get(opts, :description, "")},
        {"params", object_schema(Keyword.get(opts, :params, []), names)}
      ]

      returns = Keyword.get(opts, :returns)

      pairs =
        if returns? and returns != nil,
          do: pairs ++ [{"returns", type_schema(returns, names)}],
          else: pairs

      {name, JSON.object(pairs)}
    end)
    |> JSON.object()
  end

  # Only the action shapes that a prop refers to get a $defs entry.
  defp action_defs(components, actions, names) do
    used =
      components
      |> Enum.flat_map(fn {_name, opts} ->
        opts |> Keyword.get(:props, []) |> Enum.flat_map(&used_actions/1)
      end)
      |> Enum.uniq()

    expression =
      if "ActionExpression" in used, do: [{"ActionExpression", action_expression()}], else: []

    builtins =
      for name <- @builtin_action_refs, name in used do
        {name, builtin_action(name)}
      end

    library_actions =
      for {name, opts} <- actions, name in used do
        {name, library_action(name, Keyword.get(opts, :params, []), names)}
      end

    expression ++ builtins ++ library_actions
  end

  defp used_actions({_prop, opts}), do: type_actions(Keyword.get(opts, :type))

  defp type_actions(:action), do: ["ActionExpression"]
  defp type_actions({:actions, actions}), do: actions
  defp type_actions({:array, type}), do: type_actions(type)
  defp type_actions({:binding, type}), do: type_actions(type)
  defp type_actions({:one_of, types}), do: Enum.flat_map(types, &type_actions/1)
  defp type_actions({:object, fields}), do: Enum.flat_map(fields, &used_actions/1)
  defp type_actions(_type), do: []

  defp object_schema(fields, names) do
    required =
      for {field, opts} <- fields,
          Keyword.get(opts, :required, false) or Keyword.has_key?(opts, :default),
          do: to_string(field)

    pairs = [
      {"type", "object"},
      {"properties",
       JSON.object(
         Enum.map(fields, fn {field, opts} -> {to_string(field), prop_schema(opts, names)} end)
       )}
    ]

    pairs = if required == [], do: pairs, else: pairs ++ [{"required", required}]
    JSON.object(pairs ++ [{"additionalProperties", false}])
  end

  defp prop_schema(opts, names) do
    schema = type_schema(Keyword.fetch!(opts, :type), names)

    case Keyword.fetch(opts, :default) do
      {:ok, default} -> JSON.object([{"default", default} | schema.pairs])
      :error -> schema
    end
  end

  defp type_schema(:string, _names), do: JSON.object([{"type", "string"}])
  defp type_schema(:number, _names), do: JSON.object([{"type", "number"}])
  defp type_schema(:boolean, _names), do: JSON.object([{"type", "boolean"}])
  defp type_schema(:any, _names), do: JSON.object([])

  defp type_schema({:enum, values}, _names),
    do: JSON.object([{"type", "string"}, {"enum", values}])

  defp type_schema({:array, type}, names),
    do: JSON.object([{"type", "array"}, {"items", type_schema(type, names)}])

  defp type_schema({:object, fields}, names), do: object_schema(fields, names)
  defp type_schema({:ref, name}, _names), do: ref(name)

  defp type_schema({:one_of, types}, names),
    do: JSON.object([{"anyOf", Enum.map(types, &type_schema(&1, names))}])

  defp type_schema(:component, names),
    do: JSON.object([{"anyOf", Enum.map(names.components, &ref/1)}])

  defp type_schema(:action, _names), do: ref("ActionExpression")
  defp type_schema({:actions, [action]}, _names), do: ref(action)

  defp type_schema({:actions, actions}, _names),
    do: JSON.object([{"anyOf", Enum.map(actions, &ref/1)}])

  defp type_schema({:binding, type}, names), do: type_schema(type, names)

  defp ref(name), do: JSON.object([{"$ref", "#/$defs/" <> name}])

  defp signature(name, fields, returns, names) do
    params =
      Enum.map_join(fields, ", ", fn {field, opts} -> param_signature(field, opts, names) end)

    signature = "#{name}(#{params})"
    if returns, do: signature <> " \u2192 " <> annotation(returns, names), else: signature
  end

  # A prop with a default counts as optional, like Zod's `.default()`.
  defp param_signature(field, opts, names) do
    optional? = not Keyword.get(opts, :required, false) or Keyword.has_key?(opts, :default)

    "#{field}#{if optional?, do: "?", else: ""}: #{annotation(Keyword.fetch!(opts, :type), names)}"
  end

  defp annotation(:string, _names), do: "string"
  defp annotation(:number, _names), do: "number"
  defp annotation(:boolean, _names), do: "boolean"
  defp annotation(:any, _names), do: "any"
  defp annotation(:component, _names), do: "any"
  defp annotation({:enum, values}, _names), do: Enum.map_join(values, " | ", &~s("#{&1}"))

  defp annotation({:array, type}, names) do
    inner = annotation(type, names)
    if union?(type), do: "(#{inner})[]", else: inner <> "[]"
  end

  defp annotation({:object, fields}, names),
    do:
      "{" <>
        Enum.map_join(fields, ", ", fn {field, opts} -> param_signature(field, opts, names) end) <>
        "}"

  defp annotation({:ref, name}, _names), do: name

  defp annotation({:one_of, types}, names),
    do: Enum.map_join(types, " | ", &annotation(&1, names))

  defp annotation(:action, _names), do: "ActionExpression"
  defp annotation({:actions, actions}, _names), do: Enum.map_join(actions, " | ", &("@" <> &1))
  defp annotation({:binding, type}, names), do: "$binding<#{annotation(type, names)}>"

  defp union?({:one_of, _types}), do: true
  defp union?({:actions, [_action, _other | _rest]}), do: true
  defp union?(_type), do: false

  # The JSON shapes of the built-in action objects, as the official library
  # writes them (packages/lang-core/src/parser/builtins.ts, ACTION_DEFS).
  defp action_expression do
    JSON.object([
      {"anyOf",
       [
         action_object(
           [{"type", const("open_url")}, {"url", JSON.object([{"type", "string"}])}],
           ["type", "url"]
         ),
         action_object(
           [
             {"type", const("continue_conversation")},
             {"context", JSON.object([{"type", "string"}])}
           ],
           ["type"]
         ),
         action_object(
           [
             {"type", JSON.object([{"type", "string"}])},
             {"params",
              JSON.object([
                {"type", "object"},
                {"propertyNames", JSON.object([{"type", "string"}])},
                {"additionalProperties", JSON.object([])}
              ])}
           ],
           ["type"]
         )
       ]}
    ])
  end

  defp builtin_action("OpenUrl"),
    do:
      action_object([{"type", const("open_url")}, {"url", JSON.object([{"type", "string"}])}], [
        "type",
        "url"
      ])

  defp builtin_action("ToAssistant"),
    do:
      action_object(
        [
          {"type", const("continue_conversation")},
          {"context", JSON.object([{"type", "string"}])}
        ],
        ["type"]
      )

  defp library_action(name, params, names),
    do:
      action_object([{"type", const(name)}, {"params", object_schema(params, names)}], [
        "type",
        "params"
      ])

  defp action_object(properties, required) do
    JSON.object([
      {"type", "object"},
      {"properties", JSON.object(properties)},
      {"required", required},
      {"additionalProperties", false}
    ])
  end

  defp const(value), do: JSON.object([{"type", "string"}, {"const", value}])

  defp type_problems({name, opts}, names) do
    fields = Keyword.get(opts, :props, Keyword.get(opts, :params, []))

    Enum.flat_map(fields, fn {field, field_opts} ->
      field_problems(name, field, Keyword.get(field_opts, :type), names)
    end)
  end

  defp field_problems(owner, field, nil, _names), do: ["#{owner}.#{field} has no type"]

  defp field_problems(owner, field, type, names) do
    type
    |> refs_in()
    |> Enum.flat_map(fn
      {:component, name} ->
        if name in names.components,
          do: [],
          else: ["#{owner}.#{field} refers to #{name}, which is not a component"]

      {:action, name} ->
        if name in names.actions or name in @builtin_action_refs,
          do: [],
          else: ["#{owner}.#{field} refers to #{name}, which is not an action"]
    end)
  end

  defp refs_in({:ref, name}), do: [{:component, name}]
  defp refs_in({:actions, actions}), do: Enum.map(actions, &{:action, &1})
  defp refs_in({:array, type}), do: refs_in(type)
  defp refs_in({:binding, type}), do: refs_in(type)
  defp refs_in({:one_of, types}), do: Enum.flat_map(types, &refs_in/1)

  defp refs_in({:object, fields}),
    do: Enum.flat_map(fields, fn {_field, opts} -> refs_in(Keyword.get(opts, :type)) end)

  defp refs_in(_type), do: []
end
