defmodule OpenUI.Binding do
  @moduledoc "A two-way binding of a bindable prop to a state variable (language.md, section 5.2)."

  defstruct [:name]

  @type t :: %__MODULE__{name: String.t()}
end
