defmodule OpenUI.Runtime.Validation do
  @moduledoc """
  Field validation rules (language.md, section 5.4): `required`, `email`,
  `url`, `numeric`, `minLength`, `maxLength`, `min`, `max` and `pattern`.

  Rules run in that fixed order, since an evaluated rules object carries no
  key order, and the first failing rule names the error. Every rule except
  `required` skips empty values. Unknown rules are ignored.
  """

  alias OpenUI.Runtime.Value

  @order ~w(required email url numeric minLength maxLength min max pattern)
  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/u

  @doc "Checks `value` against `rules`; returns `{:error, rule}` for the first rule that fails."
  @spec validate(term(), map()) :: :ok | {:error, String.t()}
  def validate(value, rules) when is_map(rules) do
    Enum.find_value(@order, :ok, fn rule ->
      argument = Map.get(rules, rule)

      cond do
        argument in [nil, false] -> nil
        rule != "required" and empty?(value) -> nil
        passes?(rule, value, argument) -> nil
        true -> {:error, rule}
      end
    end)
  end

  defp empty?(value), do: value in [nil, "", []] or value == %{}

  defp passes?("required", value, _argument), do: not empty?(value)
  defp passes?("email", value, _argument), do: is_binary(value) and matches?(@email, value)
  defp passes?("url", value, _argument), do: is_binary(value) and absolute_url?(value)
  defp passes?("numeric", value, _argument) when is_number(value), do: true

  defp passes?("numeric", value, _argument) when is_binary(value),
    do: String.trim(value) != "" and parse_float(value) != :nan

  defp passes?("numeric", _value, _argument), do: false

  defp passes?("minLength", value, minimum) when is_binary(value),
    do: Value.text_length(value) >= Value.to_number(minimum)

  defp passes?("maxLength", value, maximum) when is_binary(value),
    do: Value.text_length(value) <= Value.to_number(maximum)

  defp passes?(rule, _value, _argument) when rule in ["minLength", "maxLength"], do: true

  defp passes?("min", value, minimum),
    do: compare_number(value, &(&1 >= Value.to_number(minimum)))

  defp passes?("max", value, maximum),
    do: compare_number(value, &(&1 <= Value.to_number(maximum)))

  # A pattern the regex engine cannot compile never fails the field.
  defp passes?("pattern", value, pattern) when is_binary(value) and is_binary(pattern) do
    case Regex.compile(pattern, "u") do
      {:ok, regex} -> matches?(regex, value)
      {:error, _reason} -> true
    end
  end

  defp passes?("pattern", _value, _pattern), do: true

  # A Unicode regex raises on bytes that are not UTF-8, such as text cut
  # mid-character; such text does not match.
  defp matches?(regex, value), do: String.valid?(value) and Regex.match?(regex, value)

  defp absolute_url?(value) do
    case URI.new(value) do
      {:ok, %URI{scheme: scheme, host: host}} -> scheme not in [nil, ""] and host not in [nil, ""]
      {:error, _part} -> false
    end
  end

  defp compare_number(value, compare) do
    case if(is_number(value), do: value, else: parse_float(Value.stringify(value))) do
      :nan -> true
      number -> compare.(number)
    end
  end

  # ECMAScript parseFloat: the longest numeric prefix after leading
  # whitespace, so "12abc" reads as 12.
  defp parse_float(string) do
    case Regex.run(~r/^\s*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)/, string) do
      [_match, prefix] -> Value.to_number(prefix)
      nil -> :nan
    end
  end
end
