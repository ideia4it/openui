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

  test "fails numeric for a value that is neither a number nor text" do
    assert Validation.validate(["1"], %{"numeric" => true}) == {:error, "numeric"}
    assert Validation.validate(true, %{"numeric" => true}) == {:error, "numeric"}
  end

  test "applies length and pattern rules to text only and min and max to numbers only" do
    assert Validation.validate(["a", "b", "c"], %{"maxLength" => 2, "minLength" => 5}) == :ok
    assert Validation.validate(42, %{"pattern" => "^a"}) == :ok
    assert Validation.validate("many", %{"min" => 1, "max" => 0}) == :ok
  end

  test "fails url for text that does not parse as a URL" do
    assert Validation.validate("http://exa mple.com", %{"url" => true}) == {:error, "url"}
    assert Validation.validate("https://salao365.com/agenda", %{"url" => true}) == :ok
  end
end
