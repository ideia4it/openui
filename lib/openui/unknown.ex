defmodule OpenUI.Unknown do
  @moduledoc """
  Marks where a component the library does not know sat in a list of
  components. It renders nothing, or the host's diagnostic for unknown
  components (language.md, section 10). It is not part of the canonical tree.
  """

  defstruct [:type, :statement_id, :key]

  @type t :: %__MODULE__{type: String.t(), statement_id: String.t() | nil, key: String.t() | nil}
end
