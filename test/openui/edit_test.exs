defmodule OpenUI.EditTest do
  use ExUnit.Case, async: true

  test "replaces a multi-line ternary as one statement and keeps what root still reaches" do
    current = "$dark = false\nroot = $dark\n  ? a\n  : b\na = Card(\"A\")\nb = Card(\"B\")"
    patch = "Here:\n```openui\nroot = $dark\n  ? b\n  : c\nc = Card(\"C\")\n```"

    assert OpenUI.Edit.merge(current, patch) ==
             "$dark = false\nroot = $dark\n  ? b\n  : c\nb = Card(\"B\")\nc = Card(\"C\")"
  end

  test "takes the patch statements as the program when there is no current one" do
    patch = "```openui\nroot = Stack([a])\na = Card(\"A\")\n```"

    assert OpenUI.Edit.merge("", patch) == "root = Stack([a])\na = Card(\"A\")"
  end

  test "keeps the current program when the patch holds no statement" do
    current = "root = Stack([a])\na = Card(\"A\")"

    assert OpenUI.Edit.merge(current, "Nothing to change here.") == current
  end
end
