defmodule OpenUI.Event do
  @moduledoc """
  An action that reaches the host (language.md, section 6.3):
  `continue_conversation` from `@ToAssistant`, `open_url` from `@OpenUrl`, or
  the name of a library action.

  `form_state` is read when the action runs. Inside a form it holds that
  form's fields, each as `%{"value", "componentType"}`; outside one it holds
  the page's `$variables` and page-level fields.
  """

  defstruct [:type, :form_name, human_friendly_message: "", params: %{}, form_state: %{}]

  @type t :: %__MODULE__{
          type: String.t(),
          human_friendly_message: String.t(),
          params: map(),
          form_name: String.t() | nil,
          form_state: map()
        }

  @doc "The wire form of language.md, section 6.3."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "type" => event.type,
      "humanFriendlyMessage" => event.human_friendly_message,
      "params" => event.params,
      "formName" => event.form_name,
      "formState" => event.form_state
    }
  end
end
