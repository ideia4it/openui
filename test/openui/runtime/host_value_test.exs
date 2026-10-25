defmodule OpenUI.Runtime.HostValueTest do
  use ExUnit.Case, async: true

  alias OpenUI.Runtime.HostValue

  defmodule Client do
    defstruct [:name, :visits]
  end

  test "replaces bytes that are not UTF-8 in tool text" do
    assert HostValue.normalize(%{"name" => "caf" <> <<195>>}) == %{"name" => "caf\uFFFD"}
  end

  test "writes dates and times from tools as JSON writes them" do
    values = [
      ~D[2026-10-25],
      ~T[10:00:00],
      ~N[2026-10-25 10:00:00],
      ~U[2026-10-25 10:00:00Z]
    ]

    assert HostValue.normalize(values) == values |> JSON.encode!() |> JSON.decode!()
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

  test "turns a struct with no text form into a map and every map key into text" do
    assert HostValue.normalize(%{
             client: %Client{name: "Ana", visits: 3},
             by_year: %{2025 => 10, 2026 => 12},
             by_month: %{{2026, 9} => 4, {2026, 10} => 5}
           }) == %{
             "client" => %{"name" => "Ana", "visits" => 3},
             "by_year" => %{"2025" => 10, "2026" => 12},
             "by_month" => %{"2026,9" => 4, "2026,10" => 5}
           }
  end
end
