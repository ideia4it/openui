defmodule OpenUI.BuiltinsTest do
  use ExUnit.Case, async: true

  alias OpenUI.Builtins

  test "tells built-in functions from action steps, Action counting as a step" do
    assert Enum.sort(Builtins.steps()) == ~w(OpenUrl Reset Run Set ToAssistant)

    for name <- Builtins.functions() do
      assert Builtins.function?(name)
      refute Builtins.step?(name)
    end

    for name <- ["Action" | Builtins.steps()] do
      assert Builtins.step?(name)
      refute Builtins.function?(name)
    end

    refute Builtins.step?("Percent")
  end

  test "marks as lazy only the calls that do not evaluate their arguments up front" do
    lazy = Enum.filter(Builtins.names(), &Builtins.lazy?/1)
    assert Enum.sort(lazy) == ~w(Action Each Reset Run Set)
  end
end
