defmodule OpenUI.Program.Mutation do
  @moduledoc "A `Mutation(tool, args)` statement (language.md, section 6.2)."

  defstruct [:id, :tool, :args]

  @type t :: %__MODULE__{
          id: String.t(),
          tool: OpenUI.Parser.Expression.ast() | nil,
          args: OpenUI.Parser.Expression.ast() | nil
        }
end
