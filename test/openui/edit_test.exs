defmodule OpenUI.EditTest do
  use ExUnit.Case, async: true

  test "replaces a multi-line ternary as one statement and keeps what root still reaches" do
    current = "$dark = false\nroot = $dark\n  ? a\n  : b\na = Card(\"A\")\nb = Card(\"B\")"
    patch = "Here:\n```openui\nroot = $dark\n  ? b\n  : c\nc = Card(\"C\")\n```"

    assert OpenUI.Edit.merge(current, patch) ==
             "$dark = false\nroot = $dark\n  ? b\n  : c\nb = Card(\"B\")\nc = Card(\"C\")"
  end
end
