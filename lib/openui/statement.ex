defmodule OpenUI.Statement do
  @moduledoc """
  One `name = expression` statement of a program (language.md, section 2.1).

  `pending?` marks a statement read from a cut-off tail that needed implicit
  closing; while streaming, it never replaces a completed statement of the
  same name.
  """

  defstruct [:id, :kind, :ast, source: "", pending?: false]

  @type kind :: :value | :state | :query | :mutation
  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          ast: OpenUI.Parser.Expression.ast(),
          source: String.t(),
          pending?: boolean()
        }
end
