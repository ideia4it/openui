defmodule OpenUI.Library.Component do
  @moduledoc "A component of a library: its prompt signature, description and positional props."

  defstruct [:name, description: "", signature: "", props: []]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          signature: String.t(),
          props: [OpenUI.Library.Prop.t()]
        }
end
