defmodule OpenUITest do
  use ExUnit.Case, async: true

  test "reports the OpenUI spec version it implements" do
    assert OpenUI.spec_version() == "1.0"
  end
end
