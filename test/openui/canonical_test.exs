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
end
