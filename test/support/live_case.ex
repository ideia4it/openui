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
      "tools_id" => register_tools(Keyword.get(opts, :tools)),
      "components" => Keyword.get(opts, :components, OpenUI.Test.ExampleUI)
    }

    {:ok, view, _html} =
      Phoenix.LiveViewTest.live_isolated(Phoenix.ConnTest.build_conn(), OpenUI.Test.HostLive,
        session: session
      )

    view
  end

  # The LiveView session is signed and cannot carry functions, so tool
  # providers wait in a table and the session carries their id.
  defp register_tools(nil), do: nil

  defp register_tools(tools) do
    id = System.unique_integer([:positive])
    :ets.insert(:openui_test_tools, {id, tools})
    id
  end

  @doc false
  def tools(nil), do: nil
  def tools(id), do: :ets.lookup_element(:openui_test_tools, id, 2)
end
