defmodule OpenUI.Runtime.Builtins do
  @moduledoc """
  The built-in functions that evaluate their arguments up front
  (language.md, section 3.4). `@Each` is lazy and lives in the evaluator.
  """

  alias OpenUI.Runtime.{Collation, Value}

  @doc "Calls a built-in function with evaluated, positional arguments."
  @spec call(String.t(), [term()]) :: term()
  def call(name, args), do: apply_builtin(name, args ++ List.duplicate(nil, 4))

  defp apply_builtin("Count", [array | _]) when is_list(array), do: length(array)
  defp apply_builtin("Count", _args), do: 0
  defp apply_builtin("First", [[first | _] | _]), do: first
  defp apply_builtin("First", _args), do: nil
  defp apply_builtin("Last", [[_ | _] = array | _]), do: List.last(array)
  defp apply_builtin("Last", _args), do: nil
  defp apply_builtin("Sum", [array | _]) when is_list(array), do: sum(array)
  defp apply_builtin("Sum", _args), do: 0

  defp apply_builtin("Avg", [[_ | _] = array | _]),
    do: Value.normalize_number(sum(array) / length(array))

  defp apply_builtin("Avg", _args), do: 0

  defp apply_builtin("Min", [[_ | _] = array | _]),
    do: array |> Enum.map(&Value.to_number/1) |> Enum.min()

  defp apply_builtin("Min", _args), do: 0

  defp apply_builtin("Max", [[_ | _] = array | _]),
    do: array |> Enum.map(&Value.to_number/1) |> Enum.max()

  defp apply_builtin("Max", _args), do: 0
  defp apply_builtin("Sort", [array, field, direction | _]), do: sort(array, field, direction)

  defp apply_builtin("Filter", [array, field, operator, value | _]),
    do: filter(array, field, operator, value)

  defp apply_builtin("Round", [number, decimals | _]),
    do: round_to(Value.to_number(number), decimals)

  defp apply_builtin("Abs", [number | _]), do: abs(Value.to_number(number))

  defp apply_builtin("Floor", [number | _]),
    do: number |> Value.to_number() |> Kernel.*(1.0) |> Float.floor() |> Value.normalize_number()

  defp apply_builtin("Ceil", [number | _]),
    do: number |> Value.to_number() |> Kernel.*(1.0) |> Float.ceil() |> Value.normalize_number()

  defp sum(array), do: Enum.reduce(array, 0, &Value.binary_op("+", Value.to_number(&1), &2))

  # JavaScript's Math.round: halves round up, so -2.5 gives -2.
  defp round_to(number, decimals) do
    factor = :math.pow(10, if(decimals == nil, do: 0, else: Value.to_number(decimals)))
    Value.normalize_number(Float.floor(number * factor + 0.5) / factor)
  end

  # A stable sort. Two numbers, or strings that read as numbers, compare as
  # numbers; anything else compares as text with the locale collation.
  defp sort(array, field, direction) when is_list(array) do
    descending? = direction == "desc"
    field = text(field)

    Enum.sort(array, fn left, right ->
      order = compare(read_field(left, field), read_field(right, field))
      if descending?, do: order != :lt, else: order != :gt
    end)
  end

  defp sort(other, _field, _direction), do: other

  defp compare(left, right) do
    if numeric?(left) and numeric?(right) do
      left_number = Value.to_number(left)
      right_number = Value.to_number(right)

      cond do
        left_number < right_number -> :lt
        left_number > right_number -> :gt
        true -> :eq
      end
    else
      Collation.compare(text(left), text(right))
    end
  end

  defp numeric?(value) when is_number(value), do: true
  defp numeric?(""), do: false
  defp numeric?(value) when is_binary(value), do: Value.parse_number(value) != :nan
  defp numeric?(_value), do: false

  defp filter(array, field, operator, value) when is_list(array) do
    field = text(field)
    operator = if operator == nil, do: "==", else: text(operator)
    Enum.filter(array, &matches?(read_field(&1, field), operator, value))
  end

  defp filter(_other, _field, _operator, _value), do: []

  defp matches?(field_value, "==", value), do: Value.loose_equal?(field_value, value)
  defp matches?(field_value, "!=", value), do: not Value.loose_equal?(field_value, value)

  defp matches?(field_value, operator, value) when operator in [">", "<", ">=", "<="],
    do: Value.binary_op(operator, field_value, value)

  defp matches?(field_value, "contains", value),
    do: String.contains?(text(field_value), text(value))

  defp matches?(_field_value, _unknown, _value), do: false

  # Field arguments accept dot paths; an empty field reads the element itself.
  defp read_field(item, ""), do: item

  defp read_field(item, path) do
    path
    |> String.split(".")
    |> Enum.reduce(item, fn
      key, map when is_map(map) and not is_struct(map) -> Map.get(map, key)
      _key, _other -> nil
    end)
  end

  defp text(nil), do: ""
  defp text(value), do: Value.stringify(value)
end
