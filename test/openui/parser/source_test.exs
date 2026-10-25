defmodule OpenUI.Parser.SourceTest do
  use ExUnit.Case, async: true

  alias OpenUI.Parser.Source

  defp fixture(id), do: File.read!(Path.join([OpenUI.Conformance.root(), id, "input.oui"]))

  test "joins every fence, ignores prose and keeps backticks inside double-quoted strings" do
    assert fixture("grammar/003-fence-multiple-joined")
           |> Source.prepare()
           |> String.split("\n", trim: true) ==
             ["root = Stack([a, b])", ~S|a = Text("use ``` here")|, ~S|b = Text("B")|]
  end

  test "strips comments outside strings, multi-line strings included" do
    prepared = Source.prepare(fixture("grammar/004-comment-strip"))
    refute prepared =~ "the page"
    refute prepared =~ "a note line"
    assert prepared =~ ~S|Text("a // not a comment")|
    assert prepared =~ "line one\n// still inside the string"
  end
end
