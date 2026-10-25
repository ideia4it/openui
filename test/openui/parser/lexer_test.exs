defmodule OpenUI.Parser.LexerTest do
  use ExUnit.Case, async: true

  alias OpenUI.Parser.Lexer

  test "reads a minus as part of a number only after something that is not a value" do
    assert Lexer.tokenize("[1 -2]") == [
             {:op, "["},
             {:number, 1},
             {:op, "-"},
             {:number, 2},
             {:op, "]"}
           ]

    assert Lexer.tokenize("x = -5") == [{:ident, "x"}, {:op, "="}, {:number, -5}]
    assert Enum.take(Lexer.tokenize("{a: 1} -2"), -2) == [{:op, "}"}, {:number, -2}]
  end

  test "never fails: skips unknown characters and keeps a dot after a number as member access" do
    assert Lexer.tokenize("a;b") == [{:ident, "a"}, {:ident, "b"}]
    assert Lexer.tokenize("1.") == [{:number, 1}, {:op, "."}]
    assert Lexer.tokenize("1.5e3 1e") == [{:number, 1500}, {:number, 1}]
    assert Lexer.tokenize(<<0xFF, ?a>>) == [{:ident, "a"}]
  end

  test "decodes both string quotes and flags an unterminated one" do
    assert Lexer.tokenize(~S|"q\"d\\b\ttA" 'it\'s' 'x\ny'|) ==
             [{:string, "q\"d\\b\ttA"}, {:string, "it's"}, {:string, "x\ny"}]

    assert Lexer.tokenize(~S|"abc|) == [{:string, "abc", :unterminated}]
  end

  test "reads names, calls, keywords and the short logical operators" do
    assert Lexer.tokenize("$q @Count true null Card a & b | c") ==
             [
               {:state, "$q"},
               {:at, "Count"},
               {:literal, true},
               {:literal, nil},
               {:ident, "Card"},
               {:ident, "a"},
               {:op, "&&"},
               {:ident, "b"},
               {:op, "||"},
               {:ident, "c"}
             ]
  end

  test "treats CRLF as one newline and keeps accents and emoji in strings" do
    assert Lexer.tokenize("t = Text(\"Olá 👋\")\r\nu = 1") ==
             [
               {:ident, "t"},
               {:op, "="},
               {:ident, "Text"},
               {:op, "("},
               {:string, "Olá 👋"},
               {:op, ")"},
               :newline,
               {:ident, "u"},
               {:op, "="},
               {:number, 1}
             ]
  end
end
