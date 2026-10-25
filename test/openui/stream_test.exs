defmodule OpenUI.StreamTest do
  use ExUnit.Case, async: true

  defp canonical(stream),
    do: OpenUI.Canonical.result(OpenUI.Stream.program(stream), OpenUI.Conformance.library())

  test "renders a valid page after every chunk of the worked example" do
    chunks =
      OpenUI.Conformance.root()
      |> Path.join("streaming/001-worked-example/chunks.json")
      |> File.read!()
      |> JSON.decode!()

    frames =
      Enum.scan(
        chunks,
        OpenUI.Stream.new(OpenUI.Conformance.library()),
        &OpenUI.Stream.push(&2, &1)
      )

    assert Enum.map(frames, &canonical(&1)["errors"]) == [[], [], [], []]

    assert canonical(Enum.at(frames, 0))["root"] == %{
             "type" => "Stack",
             "props" => %{"children" => []}
           }

    assert [%{"type" => "Text"}, %{"type" => "Stack", "props" => %{"children" => []}}] =
             canonical(Enum.at(frames, 1))["root"]["props"]["children"]
  end

  test "never lets a cut-off statement replace a completed one with the same name" do
    stream =
      OpenUI.Stream.new(OpenUI.Conformance.library())
      |> OpenUI.Stream.push(~s|root = Stack([t])\nt = Text("done")\nt = Text("par|)

    assert hd(canonical(stream)["root"]["props"]["children"])["props"]["text"] == "done"
    final = canonical(OpenUI.Stream.finish(stream))
    assert hd(final["root"]["props"]["children"])["props"]["text"] == "par"
  end

  test "waits for the rest of a multibyte character split across chunks" do
    <<first, rest::binary>> = "é"

    stream =
      OpenUI.Stream.new(OpenUI.Conformance.library())
      |> OpenUI.Stream.push(~s|root = Stack([Text("caf| <> <<first>>)
      |> OpenUI.Stream.push(<<rest::binary>> <> ~s|")])|)
      |> OpenUI.Stream.finish()

    assert hd(canonical(stream)["root"]["props"]["children"])["props"]["text"] == "café"
  end
end
