defmodule OpenUI.LiveCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.LiveViewTest
      import OpenUI.LiveCase
      @endpoint OpenUI.Test.Endpoint
    end
  end

  require Phoenix.LiveViewTest

  @endpoint OpenUI.Test.Endpoint

  @doc "Mounts the host page with a program and returns the view."
  def mount_program(response, opts \\ []) do
    session = %{
      "test_pid" => self(),
      "response" => response,
      "streaming" => Keyword.get(opts, :streaming, false),
      "tools" => Keyword.get(opts, :tools),
      "components" => Keyword.get(opts, :components, OpenUI.Test.ExampleUI)
    }

    {:ok, view, _html} =
      Phoenix.LiveViewTest.live_isolated(Phoenix.ConnTest.build_conn(), OpenUI.Test.HostLive,
        session: session
      )

    view
  end
end
