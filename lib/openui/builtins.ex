defmodule OpenUI.Builtins do
  @moduledoc """
  The names the language reserves for built-in functions and action steps
  (language.md, sections 1.3, 3.4 and 6.3).
  """

  @functions ~w(Count First Last Sum Avg Min Max Sort Filter Round Abs Floor Ceil Each)
  @steps ~w(Run ToAssistant OpenUrl Set Reset)

  @doc "Built-in functions, called as `@Name(...)`."
  @spec functions() :: [String.t()]
  def functions, do: @functions

  @doc "Built-in action steps, called as `@Name(...)`."
  @spec steps() :: [String.t()]
  def steps, do: @steps

  @doc "Every built-in call name, `Action` included."
  @spec names() :: [String.t()]
  def names, do: @functions ++ @steps ++ ["Action"]

  @doc "True for a built-in function."
  @spec function?(String.t()) :: boolean()
  def function?(name), do: name in @functions

  @doc "True for a built-in step or `Action`."
  @spec step?(String.t()) :: boolean()
  def step?(name), do: name in @steps or name == "Action"

  @doc """
  True for calls whose arguments are not evaluated up front: `@Each` runs its
  template per element, and `@Run`, `@Set`, `@Reset` and `Action` name their
  targets instead of evaluating them.
  """
  @spec lazy?(String.t()) :: boolean()
  def lazy?(name), do: name in ~w(Each Run Set Reset Action)
end
