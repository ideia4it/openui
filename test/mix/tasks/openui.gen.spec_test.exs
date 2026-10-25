defmodule Mix.Tasks.Openui.Gen.SpecTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Openui.Gen.Spec
  alias OpenUI.Test.ExampleLibrary

  @tag :tmp_dir
  test "writes the spec and checks it in CI", %{tmp_dir: dir} do
    out = Path.join(dir, "library.json")
    Spec.run(["OpenUI.Test.ExampleLibrary", "--out", out])

    assert File.read!(out) ==
             OpenUI.JSON.encode!(OpenUI.Library.to_spec(ExampleLibrary), pretty: true)

    assert Spec.run(["OpenUI.Test.ExampleLibrary", "--out", out, "--check"]) ==
             :ok

    File.write!(out, "{}")

    assert_raise Mix.Error, ~r/out of date/, fn ->
      Spec.run(["OpenUI.Test.ExampleLibrary", "--out", out, "--check"])
    end
  end
end
