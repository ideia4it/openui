defmodule OpenUI.ActionPlan do
  @moduledoc """
  The actions a component triggers, in order (language.md, section 6.3).

  A step is one of:

    * `{:run, statement_id, :query | :mutation}`
    * `{:to_assistant, message, context}` (`context` is `nil` when absent)
    * `{:open_url, url}`
    * `{:set, "$name", expression}`, evaluated when the action runs
    * `{:reset, ["$name"]}`
    * `{:custom, name, params}` for an action of the library
  """

  defstruct steps: []

  @type step ::
          {:run, String.t(), :query | :mutation}
          | {:to_assistant, String.t(), term()}
          | {:open_url, String.t()}
          | {:set, String.t(), OpenUI.Parser.Expression.ast()}
          | {:reset, [String.t()]}
          | {:custom, String.t(), %{String.t() => term()}}

  @type t :: %__MODULE__{steps: [step()]}
end
