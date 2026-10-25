defmodule OpenUI.CanonicalTest do
  use ExUnit.Case, async: true

  test "leaves out a prop holding a component the catalog lacks, picked from a state list" do
    library = OpenUI.Test.ExampleLibrary
    source = ~s|root = Stack([Highlight($featured[0])])\n$featured = [Badge("new")]|

    assert OpenUI.Canonical.result(OpenUI.Parser.parse(source, library), library)["root"] == %{
             "type" => "Stack",
             "props" => %{"children" => [%{"type" => "Highlight", "props" => %{}}]}
           }
  end

  test "summarizes a component that @Set stores like any other component" do
    library = OpenUI.Test.ExampleLibrary
    source = ~s|root = Stack([Button("Show", @Set($panel, Card("Billing")))])|

    root = OpenUI.Canonical.result(OpenUI.Parser.parse(source, library), library)["root"]

    assert %{"props" => %{"action" => %{"actions" => [set]}}} = hd(root["props"]["children"])

    assert set == %{
             "action" => "Set",
             "args" => ["$panel", %{"type" => "Card", "props" => %{"title" => "Billing"}}]
           }

    assert is_binary(JSON.encode!(root))
  end
end
