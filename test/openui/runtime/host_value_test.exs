defmodule OpenUI.Runtime.HostValueTest do
  use ExUnit.Case, async: true

  alias OpenUI.Runtime.HostValue

  test "replaces bytes that are not UTF-8 in tool text" do
    assert HostValue.normalize(%{"name" => "caf" <> <<195>>}) == %{"name" => "caf\uFFFD"}
  end

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
