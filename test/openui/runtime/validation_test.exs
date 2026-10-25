defmodule OpenUI.Runtime.ValidationTest do
  use ExUnit.Case, async: true

  alias OpenUI.Runtime.Validation

  test "checks text cut inside a multibyte character without raising" do
    cut = "a" <> <<195>>

    for rules <- [
          %{"email" => true},
          %{"pattern" => "^a"},
          %{"minLength" => 1},
          %{"maxLength" => 1}
        ] do
      assert Validation.validate(cut, rules) in [:ok | Enum.map(Map.keys(rules), &{:error, &1})]
    end
  end

  test "reports the first failing rule and never fails on a pattern it cannot compile" do
    assert Validation.validate("", %{"required" => true, "email" => true}) == {:error, "required"}

    assert Validation.validate("nope", %{"required" => true, "email" => true}) ==
             {:error, "email"}

    assert Validation.validate("abc", %{"pattern" => "(unclosed"}) == :ok
    assert Validation.validate(%{}, %{"minLength" => 2}) == :ok
  end
end
