defmodule OpenUI.Runtime.HostValue do
  @moduledoc """
  Turns Elixir data from the host, such as tool results, into the JSON-like
  values programs work with.

  Atom keys and atoms become strings (except `true`, `false` and `nil`),
  tuples become lists, a struct that implements `String.Chars` becomes its
  string (Decimal, Date, DateTime, as Jason would encode them), any other
  struct becomes a map, and values JSON cannot hold (pids, functions,
  references, ports) become `nil`.
  """

  alias OpenUI.Runtime.Value

  @doc "Normalizes a host value."
  @spec normalize(term()) :: term()
  def normalize(value) when value in [nil, true, false], do: value
  def normalize(value) when is_binary(value), do: value
  def normalize(value) when is_number(value), do: Value.normalize_number(value)
  def normalize(value) when is_atom(value), do: Atom.to_string(value)
  def normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  def normalize(value) when is_tuple(value), do: value |> Tuple.to_list() |> normalize()

  def normalize(%_{} = struct) do
    if String.Chars.impl_for(struct),
      do: to_string(struct),
      else: struct |> Map.from_struct() |> normalize()
  end

  def normalize(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key_string(key), normalize(item)} end)

  def normalize(_unrepresentable), do: nil

  defp key_string(key) when is_binary(key), do: key
  defp key_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_string(key), do: Value.stringify(normalize(key))
end
