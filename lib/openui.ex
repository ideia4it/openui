defmodule OpenUI do
  @moduledoc """
  An Elixir implementation of OpenUI Lang 1.0, the language a model writes to
  describe a user interface, with an optional Phoenix LiveView renderer.

  This is not an official implementation. It follows the specification at
  https://github.com/thesysdev/openui/tree/main/spec and passes its 1.0
  conformance fixtures.
  """

  @doc "The version of the OpenUI specification this library implements."
  @spec spec_version() :: String.t()
  def spec_version, do: "1.0"
end
