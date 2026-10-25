defmodule OpenUI.FixturesTest do
  use ExUnit.Case, async: true

  test "vendors every 1.0 conformance case pinned to the upstream commit" do
    assert File.read!(Path.join(OpenUI.Conformance.root(), "UPSTREAM")) =~
             "9d73d17d2bbac565672a85e78f6eb7740cb0d9ca"

    ids = OpenUI.Conformance.program_case_ids()
    assert length(ids) == 59
    assert "streaming/001-worked-example" in ids

    for id <- ids do
      files = OpenUI.Conformance.files(id)
      assert Map.has_key?(files, "expected.json") or Map.has_key?(files, "validation.json")
    end
  end
end
