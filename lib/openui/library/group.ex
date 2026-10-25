defmodule OpenUI.Library.Group do
  @moduledoc "A titled group of components in the prompt's component list."

  defstruct [:name, components: [], notes: []]

  @type t :: %__MODULE__{name: String.t(), components: [String.t()], notes: [String.t()]}
end
