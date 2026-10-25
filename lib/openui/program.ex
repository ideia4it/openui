defmodule OpenUI.Program do
  @moduledoc """
  A parsed program: its statements, the materialized entry, state defaults,
  queries, mutations and the parse metadata of language.md, section 2.

  `root` is the entry component with expressions still unevaluated in its
  props. When the entry is an expression that picks a component at runtime
  (`root = $dark ? a : b`), `root` is `nil` and `root_expression` holds it.
  """

  alias OpenUI.Program.{Mutation, Query}

  defstruct root: nil,
            root_expression: nil,
            statements: [],
            state: [],
            queries: [],
            mutations: [],
            errors: [],
            unresolved: [],
            orphans: [],
            incomplete: false

  @type t :: %__MODULE__{
          root: OpenUI.Element.t() | nil,
          root_expression: OpenUI.Parser.Expression.ast() | nil,
          statements: [OpenUI.Statement.t()],
          state: [{String.t(), term()}],
          queries: [Query.t()],
          mutations: [Mutation.t()],
          errors: [OpenUI.Error.t()],
          unresolved: [String.t()],
          orphans: [String.t()],
          incomplete: boolean()
        }
end
