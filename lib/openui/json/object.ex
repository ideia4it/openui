defmodule OpenUI.JSON.Object do
  @moduledoc """
  A JSON object that keeps the order of its keys.

  A LibrarySpec gives meaning to key order: the keys of a component's
  `properties` are its positional arguments. Elixir maps do not keep order, so
  `OpenUI.JSON.decode/1` returns objects as this struct.
  """

  defstruct pairs: []

  @type t :: %__MODULE__{pairs: [{String.t(), term()}]}

  @doc "Returns the value of `key`, or `default` when the object has no such key."
  @spec get(t(), String.t(), term()) :: term()
  def get(%__MODULE__{pairs: pairs}, key, default \\ nil) do
    case List.keyfind(pairs, key, 0) do
      {^key, value} -> value
      nil -> default
    end
  end

  @doc "Returns the keys in their order."
  @spec keys(t()) :: [String.t()]
  def keys(%__MODULE__{pairs: pairs}), do: Enum.map(pairs, &elem(&1, 0))

  defimpl JSON.Encoder do
    def encode(%{pairs: pairs}, encoder), do: :json.encode_key_value_list(pairs, encoder)
  end
end
