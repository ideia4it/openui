defmodule OpenUI.Library.Prop do
  @moduledoc """
  One positional argument of a component, function or action.

  `kind` says how the renderer treats the value: `:action` slots take action
  plans, `:components` slots take components (and reject data), everything
  else is `:value`. `bindable?` comes from the `$binding<...>` signature,
  because the schema has no marker for it.
  """

  defstruct [:name, schema: %{}, required?: false, default: :none, bindable?: false, kind: :value]

  @type t :: %__MODULE__{
          name: String.t(),
          schema: map(),
          required?: boolean(),
          default: term() | :none,
          bindable?: boolean(),
          kind: :value | :components | :action
        }
end
