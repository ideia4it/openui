defmodule OpenUI.Error do
  @moduledoc """
  An error in the shape of language.md, section 8.3, ready to send back to the
  model. `to_map/1` gives the wire form.
  """

  defstruct [
    :source,
    :code,
    :statement_id,
    :component,
    :path,
    :hint,
    :severity,
    :tool_name,
    message: ""
  ]

  @type source :: :parser | :runtime | :query | :mutation
  @type t :: %__MODULE__{
          source: source(),
          code: String.t(),
          message: String.t(),
          statement_id: String.t() | nil,
          component: String.t() | nil,
          path: String.t() | nil,
          hint: String.t() | nil,
          severity: nil | :warning,
          tool_name: String.t() | nil
        }

  @wire_keys [
    source: "source",
    code: "code",
    statement_id: "statementId",
    component: "component",
    path: "path",
    message: "message",
    hint: "hint",
    severity: "severity",
    tool_name: "toolName"
  ]

  @doc "The wire form: camelCase keys, without empty fields."
  @spec to_map(t()) :: %{String.t() => String.t()}
  def to_map(%__MODULE__{} = error) do
    for {field, key} <- @wire_keys,
        value = Map.fetch!(error, field),
        value not in [nil, ""],
        into: %{},
        do: {key, to_string(value)}
  end
end
