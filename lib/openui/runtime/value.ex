defmodule OpenUI.Runtime.Value do
  @moduledoc """
  The value semantics of OpenUI Lang (language.md, sections 3.1 and 3.2).

  The spec defines coercion, loose equality and number formatting by
  ECMAScript, so this module reproduces ToNumber, IsLooselyEqual and
  Number::toString on Elixir terms. Two differences come from the BEAM:

    * there is no NaN or Infinity, so a string that ToNumber would read as
      Infinity (`"Infinity"`, `"1e400"`) counts as 0, like NaN does;
    * arrays and objects have no identity, so loose equality compares them by
      structure.

  Numbers are integers when they hold an integral value within 2^53, and
  floats otherwise, which keeps encoded JSON identical to JavaScript's.
  """

  @max_safe_integer 9_007_199_254_740_992

  @doc "Turns an integral float into an integer and an integer beyond 2^53 into a float."
  @spec normalize_number(number()) :: number()
  def normalize_number(number) when is_integer(number) and abs(number) <= @max_safe_integer,
    do: number

  def normalize_number(number) when is_integer(number), do: number * 1.0

  def normalize_number(number) when is_float(number) do
    if abs(number) < @max_safe_integer and number == Float.round(number),
      do: trunc(number),
      else: number
  end

  @doc "ToNumber, with 0 in place of NaN."
  @spec to_number(term()) :: number()
  def to_number(number) when is_number(number), do: normalize_number(number)
  def to_number(true), do: 1
  def to_number(false), do: 0

  def to_number(string) when is_binary(string) do
    case parse_number(string) do
      :nan -> 0
      number -> number
    end
  end

  def to_number(_other), do: 0

  @doc "ToString, as `String(value)` gives it."
  @spec stringify(term()) :: String.t()
  def stringify(nil), do: "null"
  def stringify(true), do: "true"
  def stringify(false), do: "false"
  def stringify(string) when is_binary(string), do: string
  def stringify(number) when is_integer(number), do: Integer.to_string(number)
  def stringify(number) when is_float(number), do: format_float(number)

  def stringify(list) when is_list(list),
    do: Enum.map_join(list, ",", fn item -> if is_nil(item), do: "", else: stringify(item) end)

  def stringify(_object), do: "[object Object]"

  @doc """
  The length of a string as JavaScript counts it, in UTF-16 code units. Bytes
  that are not valid UTF-8, as in text cut mid-character, count one each.
  """
  @spec text_length(String.t()) :: non_neg_integer()
  def text_length(string) when is_binary(string) do
    case :unicode.characters_to_binary(string, :utf8, :utf16) do
      utf16 when is_binary(utf16) -> div(byte_size(utf16), 2)
      {_error_or_incomplete, utf16, rest} -> div(byte_size(utf16), 2) + byte_size(rest)
    end
  end

  @doc "ToBoolean."
  @spec truthy?(term()) :: boolean()
  def truthy?(value) when value in [nil, false, "", 0], do: false
  def truthy?(value) when is_float(value) and value == 0.0, do: false
  def truthy?(_value), do: true

  @doc "IsLooselyEqual (`==`)."
  @spec loose_equal?(term(), term()) :: boolean()
  def loose_equal?(nil, nil), do: true
  def loose_equal?(nil, _right), do: false
  def loose_equal?(_left, nil), do: false
  def loose_equal?(left, right) when is_number(left) and is_number(right), do: left == right
  def loose_equal?(left, right) when is_binary(left) and is_binary(right), do: left == right
  def loose_equal?(left, right) when is_boolean(left) and is_boolean(right), do: left == right
  def loose_equal?(left, right) when is_boolean(left), do: loose_equal?(to_number(left), right)
  def loose_equal?(left, right) when is_boolean(right), do: loose_equal?(left, to_number(right))

  def loose_equal?(left, right) when is_number(left) and is_binary(right),
    do: parse_number(right) == left

  def loose_equal?(left, right) when is_binary(left) and is_number(right),
    do: loose_equal?(right, left)

  def loose_equal?(left, right) when is_number(right) or is_binary(right),
    do: loose_equal?(stringify(left), right)

  def loose_equal?(left, right) when is_number(left) or is_binary(left),
    do: loose_equal?(left, stringify(right))

  def loose_equal?(left, right), do: left == right

  @doc "Applies a binary operator to two already evaluated operands."
  @spec binary_op(String.t(), term(), term()) :: term()
  def binary_op("&&", left, right), do: if(truthy?(left), do: right, else: left)
  def binary_op("||", left, right), do: if(truthy?(left), do: left, else: right)

  def binary_op("+", left, right) when is_binary(left) or is_binary(right),
    do: join_text(left) <> join_text(right)

  def binary_op("+", left, right), do: normalize_number(to_number(left) + to_number(right))
  def binary_op("-", left, right), do: normalize_number(to_number(left) - to_number(right))
  def binary_op("*", left, right), do: normalize_number(to_number(left) * to_number(right))
  def binary_op("/", left, right), do: divide(to_number(left), to_number(right))
  def binary_op("%", left, right), do: remainder(to_number(left), to_number(right))
  def binary_op("==", left, right), do: loose_equal?(left, right)
  def binary_op("!=", left, right), do: not loose_equal?(left, right)
  def binary_op(">", left, right), do: to_number(left) > to_number(right)
  def binary_op("<", left, right), do: to_number(left) < to_number(right)
  def binary_op(">=", left, right), do: to_number(left) >= to_number(right)
  def binary_op("<=", left, right), do: to_number(left) <= to_number(right)
  def binary_op(_unknown, _left, _right), do: nil

  @doc "Applies `!` or unary `-`."
  @spec unary_op(String.t(), term()) :: term()
  def unary_op("!", value), do: not truthy?(value)
  def unary_op("-", value), do: normalize_number(0 - to_number(value))

  # The spec turns a division by zero into 0 instead of Infinity or NaN.
  defp divide(_left, zero) when zero == 0, do: 0
  defp divide(left, right), do: normalize_number(left / right)

  defp remainder(_left, zero) when zero == 0, do: 0
  defp remainder(left, right) when is_integer(left) and is_integer(right), do: rem(left, right)
  defp remainder(left, right), do: normalize_number(:math.fmod(left * 1.0, right * 1.0))

  defp join_text(nil), do: ""
  defp join_text(value), do: stringify(value)

  @decimal ~r/^([+-]?)(?:(\d+)\.?(\d*)|\.(\d+))(?:[eE]([+-]?\d+))?$/

  @doc """
  StringToNumber: the number a string reads as, or `:nan`. Leading and
  trailing whitespace is ignored and the empty string is 0.
  """
  @spec parse_number(String.t()) :: number() | :nan
  def parse_number(string) when is_binary(string) do
    trimmed = String.trim(string)

    cond do
      trimmed == "" -> 0
      match = Regex.run(~r/^0[xX]([0-9a-fA-F]+)$/, trimmed) -> parse_integer(match, 16)
      match = Regex.run(~r/^0[oO]([0-7]+)$/, trimmed) -> parse_integer(match, 8)
      match = Regex.run(~r/^0[bB]([01]+)$/, trimmed) -> parse_integer(match, 2)
      match = Regex.run(@decimal, trimmed) -> parse_decimal(match)
      true -> :nan
    end
  end

  defp parse_integer([_whole, digits], base),
    do: normalize_number(String.to_integer(digits, base))

  defp parse_decimal(match) do
    [_whole, sign | rest] = match ++ List.duplicate("", 6 - length(match))
    [integer, fraction, only_fraction, exponent] = Enum.take(rest, 4)
    integer = if integer == "", do: "0", else: integer
    fraction = if only_fraction == "", do: fraction, else: only_fraction
    fraction = if fraction == "", do: "0", else: fraction
    exponent = if exponent == "", do: "0", else: exponent

    case Float.parse("#{sign}#{integer}.#{fraction}e#{exponent}") do
      {number, ""} -> normalize_number(number)
      # Out of float range: ECMAScript gives Infinity, which the BEAM cannot hold.
      :error -> :nan
    end
  end

  defp format_float(number) when number == 0.0, do: "0"
  defp format_float(number) when number < 0, do: "-" <> format_float(-number)

  defp format_float(number) do
    {digits, point} = shortest_digits(number)
    format_digits(digits, String.length(digits), point)
  end

  # The shortest round-trip digits of a positive float, with `point` the
  # position of the decimal point: value = 0.DIGITS * 10^point.
  defp shortest_digits(number) do
    {mantissa, exponent} =
      case String.split(:erlang.float_to_binary(number, [:short]), "e") do
        [mantissa, exponent] -> {mantissa, String.to_integer(exponent)}
        [mantissa] -> {mantissa, 0}
      end

    [integer, fraction] = String.split(mantissa, ".")
    digits = integer <> fraction
    point = String.length(integer) + exponent
    leading_zeros = String.length(digits) - String.length(String.trim_leading(digits, "0"))
    digits = digits |> String.trim_leading("0") |> String.trim_trailing("0")
    {digits, point - leading_zeros}
  end

  defp format_digits(digits, count, point) when count <= point and point <= 21,
    do: digits <> String.duplicate("0", point - count)

  defp format_digits(digits, _count, point) when point > 0 and point <= 21,
    do: String.slice(digits, 0, point) <> "." <> String.slice(digits, point..-1//1)

  defp format_digits(digits, _count, point) when point > -6 and point <= 0,
    do: "0." <> String.duplicate("0", -point) <> digits

  defp format_digits(digits, count, point) do
    exponent = point - 1
    sign = if exponent < 0, do: "-", else: "+"

    mantissa =
      if count == 1,
        do: digits,
        else: String.first(digits) <> "." <> String.slice(digits, 1..-1//1)

    mantissa <> "e" <> sign <> Integer.to_string(abs(exponent))
  end
end
