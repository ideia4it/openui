defmodule OpenUI.Parser.StatementsTest do
  use ExUnit.Case, async: true

  alias OpenUI.Parser.Statements

  test "completes a statement only when the next line cannot continue it" do
    assert Statements.split("a = 1\nb = 2", final: true) == {["a = 1", "b = 2"], ""}
    assert Statements.split("a = 1\nb = 2", final: false) == {["a = 1"], "b = 2"}
    assert Statements.split("s = $n > 0\n", final: false) == {[], "s = $n > 0\n"}

    assert Statements.split(~s(s = $n > 0\n  ? "a"\n  : "b"\nt = [1,\n2]\nu), final: false) ==
             {[~s(s = $n > 0\n  ? "a"\n  : "b"), "t = [1,\n2]"], "u"}

    assert Statements.split("v = \"x\ny\"\nw = 1", final: true) == {["v = \"x\ny\"", "w = 1"], ""}
  end

  test "closes a cut-off tail: string first, escape kept, then brackets in reverse" do
    assert Statements.auto_close("t = Text(\"a\\") == {"t = Text(\"a\\\\\")", true}
    assert Statements.auto_close("x = Stack([a, (b") == {"x = Stack([a, (b)])", true}
    assert Statements.auto_close("x = [1)") == {"x = [1)]", true}
    assert Statements.auto_close("x = 1") == {"x = 1", false}
  end
end
