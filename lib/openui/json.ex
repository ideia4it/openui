defmodule OpenUI.JSON do
  @moduledoc """
  JSON on top of Elixir's `JSON` that keeps the key order of objects.

  Objects decode to `OpenUI.JSON.Object`. Plain maps still encode, in map
  order.
  """

  alias OpenUI.JSON.Object

  @decoders [
    object_start: &__MODULE__.start_object/1,
    object_push: &__MODULE__.push_pair/3,
    object_finish: &__MODULE__.finish_object/2
  ]

  @doc "Decodes `binary`, returning objects as `OpenUI.JSON.Object`."
  @spec decode(binary()) :: {:ok, term()} | {:error, term()}
  def decode(binary) when is_binary(binary) do
    case JSON.decode(binary, :ok, @decoders) do
      {value, :ok, rest} ->
        if String.trim(rest) == "", do: {:ok, value}, else: {:error, :trailing_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Like `decode/1`, but raises on invalid JSON."
  @spec decode!(binary()) :: term()
  def decode!(binary) do
    case decode(binary) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid JSON: #{inspect(reason)}"
    end
  end

  @doc "Builds an ordered object from key-value pairs."
  @spec object([{String.t(), term()}]) :: Object.t()
  def object(pairs) when is_list(pairs), do: %Object{pairs: pairs}

  @doc """
  Encodes `term`. With `pretty: true`, indents with two spaces and ends with a
  newline.
  """
  @spec encode!(term(), keyword()) :: String.t()
  def encode!(term, opts \\ []) do
    if Keyword.get(opts, :pretty, false) do
      IO.iodata_to_binary([pretty(term, 0), ?\n])
    else
      JSON.encode!(term)
    end
  end

  @doc "Replaces every `OpenUI.JSON.Object` with a plain map, recursively."
  @spec to_plain(term()) :: term()
  def to_plain(%Object{pairs: pairs}),
    do: Map.new(pairs, fn {key, value} -> {key, to_plain(value)} end)

  def to_plain(list) when is_list(list), do: Enum.map(list, &to_plain/1)

  def to_plain(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {key, value} -> {key, to_plain(value)} end)

  def to_plain(value), do: value

  @doc false
  def start_object(_acc), do: []

  @doc false
  def push_pair(key, value, pairs), do: [{key, value} | pairs]

  @doc false
  def finish_object(pairs, outer_acc), do: {%Object{pairs: Enum.reverse(pairs)}, outer_acc}

  defp pretty(%Object{pairs: pairs}, depth), do: pretty_pairs(pairs, depth)

  defp pretty(map, depth) when is_map(map) and not is_struct(map),
    do: pretty_pairs(Map.to_list(map), depth)

  defp pretty([], _depth), do: "[]"

  defp pretty(list, depth) when is_list(list) do
    items = Enum.map(list, &[indent(depth + 1), pretty(&1, depth + 1)])
    ["[\n", Enum.intersperse(items, ",\n"), ?\n, indent(depth), ?]]
  end

  defp pretty(value, _depth), do: JSON.encode!(value)

  defp pretty_pairs([], _depth), do: "{}"

  defp pretty_pairs(pairs, depth) do
    entries =
      Enum.map(pairs, fn {key, value} ->
        [indent(depth + 1), JSON.encode!(key), ": ", pretty(value, depth + 1)]
      end)

    ["{\n", Enum.intersperse(entries, ",\n"), ?\n, indent(depth), ?}]
  end

  defp indent(depth), do: String.duplicate("  ", depth)
end
