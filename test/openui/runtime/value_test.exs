defmodule OpenUI.Runtime.ValueTest do
  use ExUnit.Case, async: true

  alias OpenUI.Runtime.{Collation, Value}

  test "converts to numbers like ToNumber and never produces NaN" do
    assert Enum.map(["5", " 12 ", "0x1F", ".5", "1e3", "", "abc", "12abc"], &Value.to_number/1) ==
             [5, 12, 31, 0.5, 1000, 0, 0, 0]

    assert Enum.map([true, false, nil, [1], %{}], &Value.to_number/1) == [1, 0, 0, 0, 0]
  end

  test "formats numbers like Number::toString" do
    assert Enum.map(
             [2, 3.0, 0.1 + 0.2, 1.0e21, 1.0e20, 1.0e-7, 1.0e-6, -0.0, 123.456],
             &Value.stringify/1
           ) ==
             [
               "2",
               "3",
               "0.30000000000000004",
               "1e+21",
               "100000000000000000000",
               "1e-7",
               "0.000001",
               "0",
               "123.456"
             ]
  end

  test "applies the operators of section 3.2" do
    assert Value.binary_op("*", "5", 2) == 10
    assert Value.binary_op("+", "a", nil) == "a"
    assert Value.binary_op("+", true, 1) == 2
    assert Value.binary_op("+", Value.binary_op("+", 1, 2), "x") == "3x"
    assert Value.binary_op("/", 7, 0) == 0
    assert Value.binary_op("%", 7, 0) == 0
    assert Value.binary_op("/", 7, 2) == 3.5
    assert Value.binary_op("%", -7, 3) == -1
    assert Value.binary_op(">=", 3, "3")
    assert Value.binary_op("||", nil, "fallback") == "fallback"
    assert Value.binary_op("&&", 0, "no") == 0
    assert Value.unary_op("-", "3") == -3

    assert Value.loose_equal?(5, "5") and Value.loose_equal?("", 0) and
             Value.loose_equal?(nil, nil)

    refute Value.loose_equal?(nil, 0)
    refute Value.truthy?("") or Value.truthy?(0) or Value.truthy?(nil)
    assert Value.truthy?([]) and Value.truthy?(%{}) and Value.truthy?("0")
  end

  test "compares text cut inside a multibyte character without raising" do
    assert Collation.compare("caf" <> <<195>>, "cafe") in [:lt, :eq, :gt]
  end

  test "sorts strings like the ICU root collation for letters" do
    assert Enum.sort(["b", "B", "a", "é", "Z"], &(Collation.compare(&1, &2) != :gt)) ==
             ["a", "b", "B", "é", "Z"]
  end
end
