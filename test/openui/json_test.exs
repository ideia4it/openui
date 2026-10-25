defmodule OpenUI.JSONTest do
  use ExUnit.Case, async: true

  test "decodes objects keeping key order and encodes them back in that order" do
    decoded = OpenUI.JSON.decode!(~s({"b": 1, "a": {"z": [2]}}))

    assert %OpenUI.JSON.Object{pairs: [{"b", 1}, {"a", %OpenUI.JSON.Object{pairs: [{"z", [2]}]}}]} =
             decoded

    assert OpenUI.JSON.encode!(decoded) == ~s({"b":1,"a":{"z":[2]}})

    assert OpenUI.JSON.encode!(OpenUI.JSON.object([{"k", [1]}]), pretty: true) ==
             "{\n  \"k\": [\n    1\n  ]\n}\n"

    assert OpenUI.JSON.to_plain(decoded) == %{"b" => 1, "a" => %{"z" => [2]}}
  end
end
