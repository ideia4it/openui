defmodule OpenUI.Test.Money do
  @moduledoc false
  defstruct [:cents]

  defimpl String.Chars do
    def to_string(%{cents: cents}), do: :erlang.float_to_binary(cents / 100, decimals: 2)
  end
end
