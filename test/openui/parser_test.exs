defmodule OpenUI.ParserTest do
  use ExUnit.Case, async: true

  defp library, do: OpenUI.Conformance.library()
  defp fixture(id), do: File.read!(Path.join([OpenUI.Conformance.root(), id, "input.oui"]))

  test "classifies statements, finds orphans and declares state defaults" do
    program = OpenUI.Parser.parse(fixture("evaluation/001-kind-classify"), library())
    assert Enum.map(program.queries, & &1.id) == ["data"]
    assert program.orphans == ["unused"]
    assert program.state == [{"$count", 2}]
  end

  test "auto-declares state names that are used but never declared" do
    program = OpenUI.Parser.parse(fixture("state/001-store-auto-declare"), library())
    assert program.state == [{"$v", "x"}, {"$name", nil}]
  end

  test "leaves a cycle unresolved where it closes" do
    assert OpenUI.Parser.parse(fixture("evaluation/003-ref-cycle"), library()).unresolved == ["a"]
  end

  test "drops an unknown component and reports it on its statement" do
    program = OpenUI.Parser.parse(fixture("errors/001-unknown-component-dropped"), library())

    assert [%OpenUI.Error{source: :parser, code: "unknown-component", statement_id: "chart"}] =
             program.errors
  end

  test "fills the structural fields of the error object" do
    program = OpenUI.Parser.parse(fixture("errors/005-shape-missing-required-metric"), library())
    assert [error] = program.errors

    assert error
           |> OpenUI.Error.to_map()
           |> Map.take(~w(source code statementId component path hint)) == %{
             "source" => "parser",
             "code" => "missing-required",
             "statementId" => "chart",
             "component" => "Metric",
             "path" => "/value",
             "hint" => "Signature: Metric(label*, value*). * marks required"
           }
  end

  test "falls back to the first call of the library root with a warning" do
    program = OpenUI.Parser.parse(fixture("entry/002-first-calls-root-component"), library())
    assert %OpenUI.Element{type: "Stack", statement_id: "page"} = program.root
    assert [%OpenUI.Error{code: "no-root", severity: :warning}] = program.errors
  end

  test "reports a fatal no-root when nothing can be the entry" do
    program = OpenUI.Parser.parse(fixture("entry/007-no-root-component-call"), library())
    assert program.root == nil
    assert [%OpenUI.Error{code: "no-root", severity: nil}] = program.errors
  end

  test "reports an enum mismatch on text cut inside a multibyte character" do
    program =
      OpenUI.Parser.parse(~s|root = Stack([Tag("x", "pur| <> <<195>> <> ~s|")])|, library())

    assert [%OpenUI.Error{code: "type-mismatch"}] = program.errors
  end

  test "flags a program cut inside a string as incomplete" do
    assert OpenUI.Parser.parse(~s|root = Stack([t])\nt = Text("a|, library()).incomplete
  end

  test "reports parse-failed for text with no statements and never raises on a broken library" do
    assert [%OpenUI.Error{code: "parse-failed"}] =
             OpenUI.Parser.parse("hello there", library()).errors

    assert [%OpenUI.Error{code: "parse-exception"}] =
             OpenUI.Parser.parse("root = Stack([])", :not_a_library).errors
  end
end
