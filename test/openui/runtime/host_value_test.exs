defmodule OpenUI.Runtime.HostValueTest do
  use ExUnit.Case, async: true

  alias OpenUI.Runtime.HostValue

  test "turns Elixir data from tools into JSON-like values" do
    assert HostValue.normalize(%{
             total: %OpenUI.Test.Money{cents: 1050},
             on: ~D[2026-10-25],
             status: :open,
             pair: {1, 2},
             owner: self(),
             nested: [%{ok: true, none: nil}]
           }) == %{
             "total" => "10.50",
             "on" => "2026-10-25",
             "status" => "open",
             "pair" => [1, 2],
             "owner" => nil,
             "nested" => [%{"ok" => true, "none" => nil}]
           }
  end
end
