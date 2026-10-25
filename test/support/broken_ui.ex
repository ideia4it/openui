defmodule OpenUI.Test.DummyLiveComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  def render(assigns), do: ~H|<span>live</span>|
end

defmodule OpenUI.Test.RaisingUI do
  @moduledoc false
  # Like ExampleUI, with a Highlight that raises while rendering.

  use OpenUI.LiveView.Components,
    library: OpenUI.Test.ExampleLibrary,
    fields: %{"Input" => [name: "name", type: "input"]},
    forms: %{"Form" => "name"}

  alias OpenUI.Test.ExampleUI

  for name <-
        ~w(stack card text metric line_chart series table col button form input select select_item)a do
    defdelegate unquote(name)(assigns), to: ExampleUI
  end

  def highlight(_assigns), do: raise("Highlight cannot draw this")
end

defmodule OpenUI.Test.LiveComponentUI do
  @moduledoc false
  # Like ExampleUI, with a Highlight that renders a live component.

  use OpenUI.LiveView.Components, library: OpenUI.Test.ExampleLibrary

  alias OpenUI.Test.ExampleUI

  for name <-
        ~w(stack card text metric line_chart series table col button form input select select_item)a do
    defdelegate unquote(name)(assigns), to: ExampleUI
  end

  def highlight(assigns),
    do: ~H|<.live_component module={OpenUI.Test.DummyLiveComponent} id="dummy" />|
end
