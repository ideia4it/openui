defmodule OpenUI.Parser.Validator do
  @moduledoc false
  # Checks materialized values against the JSON Schema of a prop and reports
  # the errors of language.md, section 8.2. A check returns `{:keep, value}`
  # (possibly cleaned) or `:invalid`; the caller resolves `:invalid` with
  # `resolve_invalid/2`: the default when there is one, else the optional prop
  # or array item goes away and a required one invalidates its owner.

  alias OpenUI.{Element, Error, Library, Unknown}
  alias OpenUI.Parser.Materializer

  @doc false
  def check(value, schema, _owner, _path, ctx) when not is_map(schema) or is_nil(value),
    do: {{:keep, value}, ctx}

  def check(value, _schema, _owner, _path, ctx) when is_tuple(value) or value == :null,
    do: {{:keep, value}, ctx}

  def check(%Unknown{} = value, _schema, _owner, _path, ctx), do: {{:keep, value}, ctx}

  def check(%Element{} = element, schema, owner, path, ctx) do
    if not composite?(schema) and data_shape?(schema) do
      expected = if is_binary(schema["type"]), do: schema["type"], else: "a literal value"
      {:invalid, mismatch(ctx, owner, path, expected, ~s(component "#{element.type}"))}
    else
      {{:keep, element}, ctx}
    end
  end

  def check(value, schema, owner, path, ctx) do
    cond do
      composite?(schema) -> check_slot(value, schema, owner, path, ctx)
      schema["type"] == "object" -> check_object(value, schema, owner, path, ctx)
      schema["type"] == "array" -> check_array(value, schema, owner, path, ctx)
      true -> check_leaf(value, schema, owner, path, ctx)
    end
  end

  @doc false
  def resolve_invalid(required?, :none), do: if(required?, do: :invalid, else: :remove)
  def resolve_invalid(_required?, default), do: {:keep, default}

  @doc false
  def default_of(schema) when is_map(schema), do: Map.get(schema, "default", :none)
  def default_of(_schema), do: :none

  @doc false
  def issue(%Materializer{} = ctx, owner, path, code, details \\ []) do
    error = %Error{
      source: :parser,
      code: code,
      component: owner,
      path: path,
      statement_id: ctx.statement_id,
      message: message(code, owner, path, details),
      hint: hint(code, owner, ctx.library, details),
      severity: Keyword.get(details, :severity)
    }

    %{ctx | errors: [error | ctx.errors]}
  end

  @doc false
  def signature_hint(library, owner) do
    params = params_of(library, owner)
    "Signature: #{owner}(#{Enum.map_join(params, ", ", &starred/1)}). * marks required"
  end

  defp starred(%{required?: true, name: name}), do: name <> "*"
  defp starred(%{name: name}), do: name

  # A component in a slot that only takes data, such as a string or a list.
  defp data_shape?(schema),
    do: is_binary(schema["type"]) or is_list(schema["enum"]) or Map.has_key?(schema, "const")

  defp composite?(schema), do: Enum.any?(~w($ref anyOf oneOf allOf), &Map.has_key?(schema, &1))

  # A slot whose every option is a component takes any component, never data.
  defp check_slot(value, schema, owner, path, ctx) do
    names = slot_ref_names(schema)

    if names != [] and Enum.all?(names, &(Library.component(ctx.library, &1) != nil)) do
      {:invalid, mismatch(ctx, owner, path, Enum.join(names, " | "), slot_actual(value))}
    else
      {{:keep, value}, ctx}
    end
  end

  defp slot_ref_names(schema) do
    schema
    |> Map.get("anyOf", Map.get(schema, "oneOf", [schema]))
    |> Enum.map(fn option -> ref_name(option) end)
  end

  defp ref_name(%{"$ref" => "#/$defs/" <> name}), do: name
  defp ref_name(_option), do: nil

  defp slot_actual(value) when is_list(value), do: "array"
  defp slot_actual(value) when is_map(value), do: "plain object"
  defp slot_actual(value), do: js_typeof(value)

  defp check_array(value, schema, owner, path, ctx) when is_list(value) do
    case schema["items"] do
      items when is_map(items) -> check_items(value, items, owner, path, ctx)
      _no_items -> {{:keep, value}, ctx}
    end
  end

  defp check_array(value, _schema, owner, path, ctx),
    do: {:invalid, mismatch(ctx, owner, path, "array", js_type(value))}

  # Invalid items are left out; error paths keep the original indices.
  defp check_items(items, item_schema, owner, path, ctx) do
    {kept, ctx} =
      items
      |> Enum.with_index()
      |> Enum.reduce({[], ctx}, fn {item, index}, {kept, ctx} ->
        keep_valid(check(item, item_schema, owner, "#{path}/#{index}", ctx), kept)
      end)

    {{:keep, Enum.reverse(kept)}, ctx}
  end

  defp keep_valid({{:keep, item}, ctx}, kept), do: {[item | kept], ctx}
  defp keep_valid({:invalid, ctx}, kept), do: {kept, ctx}

  defp check_object(value, schema, owner, path, ctx)
       when is_map(value) and not is_struct(value) do
    properties = Map.get(schema, "properties", %{})
    required = Map.get(schema, "required", [])
    {value, invalid?, ctx} = fill_required(value, properties, required, owner, path, ctx)

    {value, invalid?, ctx} =
      Enum.reduce(properties, {value, invalid?, ctx}, fn {key, sub_schema},
                                                         {object, invalid?, ctx} ->
        check_field(object, key, sub_schema, key in required, {owner, path}, invalid?, ctx)
      end)

    if invalid?, do: {:invalid, ctx}, else: {{:keep, value}, ctx}
  end

  defp check_object(value, _schema, owner, path, ctx),
    do: {:invalid, mismatch(ctx, owner, path, "object", js_type(value))}

  defp check_field(object, key, sub_schema, required?, {owner, path}, invalid?, ctx) do
    if Map.has_key?(object, key) do
      object[key]
      |> check(sub_schema, owner, "#{path}/#{key}", ctx)
      |> put_field(object, key, resolve_invalid(required?, default_of(sub_schema)), invalid?)
    else
      {object, invalid?, ctx}
    end
  end

  defp put_field({{:keep, field}, ctx}, object, key, _resolution, invalid?),
    do: {Map.put(object, key, field), invalid?, ctx}

  defp put_field({:invalid, ctx}, object, _key, :invalid, _invalid?), do: {object, true, ctx}

  defp put_field({:invalid, ctx}, object, key, :remove, invalid?),
    do: {Map.delete(object, key), invalid?, ctx}

  defp put_field({:invalid, ctx}, object, key, {:keep, default}, invalid?),
    do: {Map.put(object, key, default), invalid?, ctx}

  # While the text may still grow, a required key can still arrive.
  defp fill_required(value, _properties, _required, _owner, _path, %{partial?: true} = ctx),
    do: {value, false, ctx}

  defp fill_required(value, properties, required, owner, path, ctx) do
    Enum.reduce(required, {value, false, ctx}, fn key, {object, invalid?, ctx} ->
      cond do
        Map.get(object, key) != nil ->
          {object, invalid?, ctx}

        default_of(properties[key]) != :none ->
          {Map.put(object, key, default_of(properties[key])), invalid?, ctx}

        true ->
          {object, true, absent_issue(ctx, object, key, owner, "#{path}/#{key}")}
      end
    end)
  end

  @doc false
  def absent_issue(ctx, props, key, owner, path) do
    code = if Map.has_key?(props, key), do: "null-required", else: "missing-required"
    issue(ctx, owner, path, code)
  end

  # Enum membership waits while the text may still grow: a cut literal can
  # still complete into a valid member. A wrong scalar type cannot.
  defp check_leaf(value, schema, owner, path, ctx) do
    cond do
      is_list(schema["enum"]) -> check_enum(value, schema["enum"], owner, path, ctx)
      Map.has_key?(schema, "const") -> check_enum(value, [schema["const"]], owner, path, ctx)
      expected = scalar_type(schema["type"]) -> check_type(value, expected, owner, path, ctx)
      true -> {{:keep, value}, ctx}
    end
  end

  defp check_enum(value, _members, _owner, _path, %{partial?: true} = ctx),
    do: {{:keep, value}, ctx}

  defp check_enum(value, members, owner, path, ctx) do
    if not scalar?(value) or Enum.any?(members, &(&1 == value)) do
      {{:keep, value}, ctx}
    else
      expected = "one of [" <> Enum.map_join(members, ", ", &quote_value/1) <> "]"
      {:invalid, mismatch(ctx, owner, path, expected, quote_value(value))}
    end
  end

  defp check_type(value, expected, owner, path, ctx) do
    if js_typeof(value) == expected,
      do: {{:keep, value}, ctx},
      else: {:invalid, mismatch(ctx, owner, path, expected, js_type(value))}
  end

  # Model text may be cut inside a multibyte character, which JSON cannot
  # encode; its stray bytes become U+FFFD.
  defp quote_value(value) when is_binary(value),
    do: value |> String.replace_invalid() |> JSON.encode!()

  defp quote_value(value), do: JSON.encode!(value)

  defp scalar_type("string"), do: "string"
  defp scalar_type(type) when type in ["number", "integer"], do: "number"
  defp scalar_type("boolean"), do: "boolean"
  defp scalar_type(_type), do: nil

  defp scalar?(value), do: is_binary(value) or is_number(value) or is_boolean(value)

  defp js_typeof(value) when is_binary(value), do: "string"
  defp js_typeof(value) when is_number(value), do: "number"
  defp js_typeof(value) when is_boolean(value), do: "boolean"
  defp js_typeof(_value), do: "object"

  defp js_type(value) when is_list(value), do: "array"
  defp js_type(value), do: js_typeof(value)

  defp mismatch(ctx, owner, path, expected, actual),
    do: issue(ctx, owner, path, "type-mismatch", expected: expected, actual: actual)

  defp params_of(library, owner) do
    case Library.component(library, owner) || Library.function(library, owner) ||
           Library.action(library, owner) do
      %{props: props} -> props
      %{params: params} -> params
    end
  end

  defp message("type-mismatch", _owner, path, details),
    do: ~s(field "#{path}" expects #{details[:expected]} but got #{details[:actual]})

  defp message("missing-required", _owner, path, _details),
    do: ~s(missing required field "#{path}")

  defp message("null-required", _owner, path, _details),
    do: ~s(required field "#{path}" cannot be null)

  defp message("unknown-component", owner, _path, _details),
    do: ~s(Unknown component "#{owner}": not found in the library or the built-ins)

  defp message("inline-reserved", owner, _path, _details),
    do: "#{owner}() must be declared as a top-level statement, not used inline as a value"

  defp message("excess-args", owner, _path, details) do
    declared = details[:declared]
    got = details[:got]
    "#{owner} takes #{declared} arg(s), got #{got} (#{got - declared} excess dropped)"
  end

  defp message("unknown-function", owner, _path, _details),
    do:
      ~s(Unknown function "@#{owner}": not a built-in, a library function or an action. The call evaluates to null)

  defp message("no-root", owner, _path, details) do
    case details[:reason] do
      :not_component ->
        "root does not evaluate to a component"

      :fallback ->
        "No root statement. Rendering the first statement that calls the root component #{owner}"

      :missing when owner in [nil, ""] ->
        "No root statement"

      :missing ->
        "No root statement, and no statement calls the root component #{owner}"
    end
  end

  defp hint("unknown-component", _owner, library, _details),
    do: "Available components: " <> Enum.map_join(library.components, ", ", & &1.name)

  defp hint("unknown-function", _owner, library, _details) do
    names = Enum.map(library.functions, & &1.name) ++ OpenUI.Builtins.functions()
    "Available functions: " <> Enum.map_join(names, ", ", &("@" <> &1))
  end

  defp hint("inline-reserved", owner, _library, _details),
    do: "Declare it as a top-level statement: myVar = #{owner}(...)"

  defp hint(code, owner, library, _details)
       when code in ["missing-required", "null-required", "type-mismatch", "excess-args"],
       do: signature_hint(library, owner)

  defp hint(_code, _owner, _library, _details), do: nil
end
