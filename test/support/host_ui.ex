defmodule OpenUI.Test.HostLibrary do
  @moduledoc false
  use OpenUI.Library, root: "Note"

  component "Note",
    description: "A line of text with a unit the host supplies",
    props: [text: [type: :string, required: true]]
end

defmodule OpenUI.Test.HostUI do
  @moduledoc false
  use OpenUI.LiveView.Components, library: OpenUI.Test.HostLibrary

  def note(assigns), do: ~H|<p class="note" data-unit={@host[:unit]}>{@text}</p>|
end
