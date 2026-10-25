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

  @tag :tmp_dir
  test "fails the check when the spec file was never written", %{tmp_dir: dir} do
    out = Path.join(dir, "library.json")

    assert_raise Mix.Error, ~r/out of date/, fn ->
      Spec.run(["OpenUI.Test.ExampleLibrary", "--out", out, "--check"])
    end

    refute File.exists?(out)
  end

  @tag :tmp_dir
  test "fails the check when the catalog would break programs stored with the committed spec",
       %{tmp_dir: dir} do
    out = Path.join(dir, "library.json")

    File.write!(out, ~S"""
    {"schema": {"properties": {"Card": {"$ref": "#/$defs/Card"}},
                "$defs": {"Card": {"type": "object",
                                   "properties": {"children": {"type": "array"}, "title": {"type": "string"}}}}}}
    """)

    assert_raise Mix.Error, ~r/would break stored programs:\nCard: prop children moved/, fn ->
      Spec.run(["OpenUI.Test.ExampleLibrary", "--out", out, "--check"])
    end
  end

  test "refuses to run without one module and an --out path" do
    assert_raise Mix.Error, ~r/Usage: mix openui.gen.spec/, fn ->
      Spec.run(["OpenUI.Test.ExampleLibrary"])
    end
  end

  @tag :tmp_dir
  test "refuses a module that does not define a catalog", %{tmp_dir: dir} do
    out = Path.join(dir, "library.json")

    assert_raise Mix.Error, ~r/OpenUI.Library is not a module that uses OpenUI.Library/, fn ->
      Spec.run(["OpenUI.Library", "--out", out])
    end

    assert_raise Mix.Error, ~r/Missing.Catalog is not a module that uses OpenUI.Library/, fn ->
      Spec.run(["Missing.Catalog", "--out", out])
    end

    refute File.exists?(out)
  end
end
