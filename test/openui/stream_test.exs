defmodule OpenUI.StreamTest do
  use ExUnit.Case, async: true

  defp canonical(stream),
    do: OpenUI.Canonical.result(OpenUI.Stream.program(stream), OpenUI.Conformance.library())

  defp first_text(stream), do: hd(canonical(stream)["root"]["props"]["children"])["props"]["text"]

  defp start(chunk),
    do: OpenUI.Conformance.library() |> OpenUI.Stream.new() |> OpenUI.Stream.push(chunk)

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

  test "holds back the bytes of a three- or four-byte character cut by a chunk" do
    <<euro_head::binary-size(2), euro_tail::binary>> = "€"
    <<party_head::binary-size(3), party_tail::binary>> = "🎉"

    stream = start(~s|root = Stack([Text("5| <> euro_head)
    assert first_text(stream) == "5"

    stream = OpenUI.Stream.push(stream, euro_tail <> " " <> party_head)
    assert first_text(stream) == "5€"

    stream = OpenUI.Stream.push(stream, party_tail <> ~s|")])|)
    assert first_text(stream) == "5€ 🎉"
  end

  test "shows bytes that can start no character as they come, without raising" do
    assert first_text(start(~s|root = Stack([Text("ab| <> <<0x82>>)) == "ab\uFFFD"

    stream = start(<<0xFF>>)
    assert OpenUI.Stream.program(stream).errors == []
    assert OpenUI.Stream.text(stream) == <<0xFF>>
  end

  test "renders the completed statements while the name of the next one is arriving" do
    assert first_text(start(~s|root = Stack([t])\nt = Text("done")\nfo|)) == "done"
  end

  test "declares a $name cut at the end of a chunk only when a completed statement uses it" do
    assert canonical(start(~s|root = Stack([a])\na = Text($qu|))["state"] == %{}

    assert canonical(start(~s|root = Stack([a, b])\na = Text($q)\nb = Text($q|))["state"] ==
             %{"$q" => nil}
  end

  test "drops a statement read from prose once a later chunk opens the code fence" do
    stream =
      start("Total = open + closed tickets\nHere is the page:\n")
      |> OpenUI.Stream.push("```openui\nroot = Stack([])\n")

    assert Enum.map(OpenUI.Stream.program(stream).statements, & &1.id) == ["root"]
    assert canonical(stream)["root"] == %{"type" => "Stack", "props" => %{"children" => []}}
  end

  test "starts over with a chunk pushed after finish, and finishing twice changes nothing" do
    finished = OpenUI.Stream.finish(start(~s|root = Stack([Text("first")])|))
    assert OpenUI.Stream.finish(finished) == finished

    next = OpenUI.Stream.push(finished, ~s|root = Stack([Text("second")])|)

    refute OpenUI.Stream.finished?(next)
    assert OpenUI.Stream.text(next) == ~s|root = Stack([Text("second")])|
    assert first_text(next) == "second"
  end

  test "reports a failure of the parser itself instead of raising, like a batch parse" do
    stream =
      %OpenUI.Library{components: nil}
      |> OpenUI.Stream.new()
      |> OpenUI.Stream.push("root = Stack([])")

    assert [%OpenUI.Error{code: "parse-exception"}] = OpenUI.Stream.program(stream).errors
  end
end
