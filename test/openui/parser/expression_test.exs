defmodule OpenUI.Parser.ExpressionTest do
  use ExUnit.Case, async: true

  alias OpenUI.Parser.{Expression, Lexer}

  defp parse(source), do: source |> Lexer.tokenize() |> Expression.parse()

  test "follows the precedence table from ternary down to postfix" do
    assert parse("1 + 2 * 3 - 4 / 2") ==
             {:binary, "-",
              {:binary, "+", {:number, 1}, {:binary, "*", {:number, 2}, {:number, 3}}},
              {:binary, "/", {:number, 4}, {:number, 2}}}

    assert parse("a ? b : c ? d : e") ==
             {:ternary, {:ref, "a"}, {:ref, "b"},
              {:ternary, {:ref, "c"}, {:ref, "d"}, {:ref, "e"}}}

    assert parse("!!x") == {:unary, "!", {:unary, "!", {:ref, "x"}}}

    assert parse("1 || 2 && 0") ==
             {:binary, "||", {:number, 1}, {:binary, "&&", {:number, 2}, {:number, 0}}}
  end

  test "reads calls, object keys and member fields the way the grammar says" do
    assert parse("Stack([a b,])") == {:component, "Stack", [{:array, [{:ref, "a"}, {:ref, "b"}]}]}

    assert parse(~S|{name: "x", "quoted key": 1, 2: "two", $s: 3, Card: 4}|) ==
             {:object,
              [
                {"name", {:string, "x"}},
                {"quoted key", {:number, 1}},
                {"2", {:string, "two"}},
                {"s", {:number, 3}},
                {"Card", {:number, 4}}
              ]}

    assert parse("m.0.1") == {:member, {:ref, "m"}, "0.1"}
    assert parse("m[0][1]") == {:index, {:index, {:ref, "m"}, {:number, 0}}, {:number, 1}}
    assert parse("Count(x)") == {:ref, "Count"}

    assert parse("Action([@Set($a, 1)])") ==
             {:call, "Action", [{:array, [{:call, "Set", [{:state, "$a"}, {:number, 1}]}]}]}

    assert parse("foo.bar(x)") == {:member, {:ref, "foo"}, "bar"}
  end

  test "classifies statements by their right side" do
    assert %OpenUI.Statement{id: "$x", kind: :query} =
             Expression.parse_statement(~S|$x = Query("t", {}, {})|)

    assert %OpenUI.Statement{id: "m", kind: :mutation} =
             Expression.parse_statement(~S|m = Mutation("t", {})|)

    assert %OpenUI.Statement{id: "$n", kind: :state, ast: {:number, 1}} =
             Expression.parse_statement("$n = 1")

    assert %OpenUI.Statement{id: "t", kind: :value} =
             Expression.parse_statement(~S|t = Text("a")|)

    assert Expression.parse_statement("just prose") == nil
  end
end
