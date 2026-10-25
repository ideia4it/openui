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

  test "reports text that is not JSON, and decode! raises on it" do
    assert {:error, _reason} = OpenUI.JSON.decode(~s({"a": ))
    assert_raise ArgumentError, ~r/invalid JSON/, fn -> OpenUI.JSON.decode!(~s({"a": )) end
  end

  test "turns objects inside plain maps into maps and pretty-prints plain maps and empty lists" do
    assert OpenUI.JSON.to_plain(%{"spec" => OpenUI.JSON.object([{"k", 1}])}) ==
             %{"spec" => %{"k" => 1}}

    assert OpenUI.JSON.encode!(%{"tags" => []}, pretty: true) == "{\n  \"tags\": []\n}\n"
  end
end
