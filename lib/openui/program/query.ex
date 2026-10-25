defmodule OpenUI.Program.Query do
  @moduledoc """
  A `Query(tool, args, defaults, refresh)` statement (language.md, section 6.1).
  `deps` are the state variables written literally in `args`: a change in one
  of them fetches again.
  """

  defstruct [:id, :tool, :args, :defaults, :refresh, deps: []]

  @type t :: %__MODULE__{
          id: String.t(),
          tool: OpenUI.Parser.Expression.ast() | nil,
          args: OpenUI.Parser.Expression.ast() | nil,
          defaults: OpenUI.Parser.Expression.ast() | nil,
          refresh: OpenUI.Parser.Expression.ast() | nil,
          deps: [String.t()]
        }
end
