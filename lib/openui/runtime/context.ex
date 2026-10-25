defmodule OpenUI.Runtime.Context do
  @moduledoc """
  What evaluation reads: the library, the state store, the current result of
  each query and the status of each mutation.

  `queries` maps a query id to its latest result (or its defaults before the
  first one). `mutations` maps a mutation id to `%{"status", "data",
  "error"}`; an absent mutation reads as idle.
  """

  defstruct [:library, state: %{}, queries: %{}, mutations: %{}]

  @type t :: %__MODULE__{
          library: OpenUI.Library.t(),
          state: %{String.t() => term()},
          queries: %{String.t() => term()},
          mutations: %{String.t() => map()}
        }
end
