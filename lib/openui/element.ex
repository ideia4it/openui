defmodule OpenUI.Element do
  @moduledoc """
  A component in a program tree. `props` maps prop names to values; before
  evaluation a value may still be an expression.

  `statement_id` names the statement the component came from, when it came
  from one. `key` is its path in the evaluated tree (`"0"` for the entry,
  `"0.children.1"` for the entry's second child) and addresses it for
  interactions.
  """

  defstruct [:type, :statement_id, :key, props: %{}]

  @type t :: %__MODULE__{
          type: String.t(),
          props: %{String.t() => term()},
          statement_id: String.t() | nil,
          key: String.t() | nil
        }
end
