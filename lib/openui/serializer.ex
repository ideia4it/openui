defmodule OpenUI.Serializer do
  @moduledoc """
  Writes a rendered tree back to OpenUI Lang (language.md, section 9.2).

  The entry comes first; every other component with a statement name becomes
  its own statement, children before parents. Props go by position, `null`
  holds an unfilled position and trailing nulls of optional props are
  trimmed. Query and mutation statements do not round-trip.
  """

  alias OpenUI.{ActionPlan, Binding, Element, Library, Unknown}
  alias OpenUI.Runtime.Value

  @precedence %{
    "||" => 2,
    "&&" => 3,
    "==" => 4,
    "!=" => 4,
    ">" => 5,
    "<" => 5,
    ">=" => 5,
    "<=" => 5,
    "+" => 6,
    "-" => 6,
    "*" => 7,
    "/" => 7,
    "%" => 7
  }
  @ternary_precedence 1
  @unary_precedence 8

  @doc """
  Serializes an evaluated tree. `state:` adds `$name = value` declarations
  after the components (nil values are skipped).
  """
  @spec to_source(Element.t(), Library.t() | module(), keyword()) :: String.t()
  def to_source(%Element{} = tree, library, opts \\ []) do
    library = Library.resolve(library)
    {root_expression, statements} = element_expression(tree, library, [])
    root_id = tree.statement_id || "root"

    component_lines =
      statements
      |> Enum.reverse()
      |> Enum.reject(fn {id, _text} -> id == root_id end)
      |> Enum.map(fn {id, text} -> "#{id} = #{text}" end)

    state_lines =
      for {name, value} <- Keyword.get(opts, :state, %{}), value != nil do
        {text, _statements} = value(value, library, [])
        "#{name} = #{text}"
      end

    Enum.join(["#{root_id} = #{root_expression}" | component_lines] ++ state_lines, "\n")
  end

  @doc "Serializes an expression, adding the parentheses its grouping needs."
  @spec expression(OpenUI.Parser.Expression.ast()) :: String.t()
  def expression({:string, string}), do: JSON.encode!(string)
  def expression({:number, number}), do: Value.stringify(number)
  def expression({:boolean, boolean}), do: to_string(boolean)
  def expression(:null), do: "null"
  def expression({:literal, value}), do: value |> value(nil, []) |> elem(0)
  def expression({kind, name}) when kind in [:ref, :state, :unresolved], do: name
  def expression({:runtime_ref, name, _kind}), do: name
  def expression({:array, items}), do: "[" <> Enum.map_join(items, ", ", &expression/1) <> "]"

  def expression({:object, entries}),
    do:
      "{" <>
        Enum.map_join(entries, ", ", fn {key, value} -> "#{key}: #{expression(value)}" end) <> "}"

  def expression({:binary, op, left, right}) do
    precedence = Map.fetch!(@precedence, op)
    "#{operand(left, precedence, :left)} #{op} #{operand(right, precedence, :right)}"
  end

  def expression({:unary, op, operand}), do: op <> operand(operand, @unary_precedence, :right)

  def expression({:ternary, condition, then_branch, else_branch}),
    do:
      "#{operand(condition, @ternary_precedence + 1, :left)} ? #{expression(then_branch)} : #{expression(else_branch)}"

  def expression({:member, object, field}), do: "#{operand(object, 9, :left)}.#{field}"

  def expression({:index, object, index}),
    do: "#{operand(object, 9, :left)}[#{expression(index)}]"

  def expression({:assign, name, value}), do: "#{name} = #{expression(value)}"

  def expression({:component, name, args}),
    do: "#{name}(#{Enum.map_join(args, ", ", &expression/1)})"

  def expression({:call, "Action", args}),
    do: "Action(#{Enum.map_join(args, ", ", &expression/1)})"

  def expression({:call, name, args}), do: "@#{name}(#{Enum.map_join(args, ", ", &expression/1)})"

  # A child binds looser than its parent: on the left, a lower precedence
  # needs parentheses; on the right, an equal one does too, because
  # `a - (b - c)` and `"a" + (1 + 2)` would regroup without them.
  defp operand(ast, parent_precedence, side) do
    text = expression(ast)
    precedence = precedence_of(ast)

    if precedence < parent_precedence or (side == :right and precedence == parent_precedence),
      do: "(#{text})",
      else: text
  end

  defp precedence_of({:binary, op, _left, _right}), do: Map.fetch!(@precedence, op)
  defp precedence_of({:ternary, _condition, _then, _else}), do: @ternary_precedence
  defp precedence_of({:unary, _op, _operand}), do: @unary_precedence
  defp precedence_of(_ast), do: 10

  defp element_expression(%Element{} = element, library, statements) do
    case Library.component(library, element.type) do
      nil ->
        positional(element.type, Map.values(element.props), [], library, statements)

      component ->
        positional(
          element.type,
          Enum.map(component.props, &element.props[&1.name]),
          component.props,
          library,
          statements
        )
    end
  end

  defp positional(name, values, params, library, statements) do
    {args, statements} = Enum.map_reduce(values, statements, &value(&1, library, &2))
    {"#{name}(#{args |> trim_optional_nulls(params) |> Enum.join(", ")})", statements}
  end

  defp trim_optional_nulls(args, params) do
    required = params |> Enum.take(length(args)) |> Enum.map(& &1.required?)

    args
    |> Enum.zip(required ++ List.duplicate(false, length(args) - length(required)))
    |> Enum.reverse()
    |> Enum.drop_while(fn {arg, required?} -> arg == "null" and not required? end)
    |> Enum.reverse()
    |> Enum.map(&elem(&1, 0))
  end

  defp value(nil, _library, statements), do: {"null", statements}

  defp value(string, _library, statements) when is_binary(string),
    do: {JSON.encode!(string), statements}

  defp value(number, _library, statements) when is_number(number),
    do: {Value.stringify(number), statements}

  defp value(boolean, _library, statements) when is_boolean(boolean),
    do: {to_string(boolean), statements}

  defp value(%Binding{name: name}, _library, statements), do: {name, statements}
  defp value(%Unknown{}, _library, statements), do: {"null", statements}
  defp value(%ActionPlan{} = plan, library, statements), do: {plan(plan, library), statements}

  defp value(%Element{statement_id: nil} = element, library, statements),
    do: element_expression(element, library, statements)

  defp value(%Element{statement_id: id} = element, library, statements) do
    if List.keymember?(statements, id, 0) do
      {id, statements}
    else
      {text, statements} = element_expression(element, library, statements)
      {id, [{id, text} | statements]}
    end
  end

  defp value(list, library, statements) when is_list(list) do
    {items, statements} =
      list
      |> Enum.reject(&match?(%Unknown{}, &1))
      |> Enum.map_reduce(statements, &value(&1, library, &2))

    {"[" <> Enum.join(items, ", ") <> "]", statements}
  end

  defp value(map, library, statements) when is_map(map) do
    {entries, statements} =
      Enum.map_reduce(map, statements, fn {key, item}, statements ->
        {text, statements} = value(item, library, statements)
        {"#{key}: #{text}", statements}
      end)

    {"{" <> Enum.join(entries, ", ") <> "}", statements}
  end

  defp plan(%ActionPlan{steps: [step]}, library), do: step(step, library)

  defp plan(%ActionPlan{steps: steps}, library),
    do: "Action([" <> Enum.map_join(steps, ", ", &step(&1, library)) <> "])"

  defp step({:to_assistant, message, nil}, _library), do: "@ToAssistant(#{JSON.encode!(message)})"

  defp step({:to_assistant, message, context}, library),
    do: "@ToAssistant(#{JSON.encode!(message)}, #{context |> value(library, []) |> elem(0)})"

  defp step({:open_url, url}, _library), do: "@OpenUrl(#{JSON.encode!(url)})"
  defp step({:set, name, value}, _library), do: "@Set(#{name}, #{expression(value)})"
  defp step({:reset, targets}, _library), do: "@Reset(#{Enum.join(targets, ", ")})"
  defp step({:run, statement_id, _kind}, _library), do: "@Run(#{statement_id})"

  defp step({:custom, name, params}, library) do
    keys =
      case library && Library.action(library, name) do
        nil -> params |> Map.keys() |> Enum.sort()
        action -> Enum.map(action.params, & &1.name)
      end

    args = Enum.map_join(keys, ", ", &(params |> Map.get(&1) |> value(library, []) |> elem(0)))
    "@#{name}(#{args})"
  end
end
