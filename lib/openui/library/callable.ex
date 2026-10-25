defmodule OpenUI.Library.Callable do
  @moduledoc """
  A custom function or action of a library.

  `impl` is set only for functions: it receives one map keyed by the param
  names and returns the result. Actions run in the host, never here.
  """

  defstruct [:name, :returns, :impl, description: "", signature: "", params: []]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          signature: String.t(),
          params: [OpenUI.Library.Prop.t()],
          returns: map() | nil,
          impl: (map() -> term()) | nil
        }
end
