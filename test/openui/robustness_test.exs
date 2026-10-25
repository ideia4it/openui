defmodule OpenUI.RobustnessTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OpenUI.Conformance

  property "parsing and rendering never raise, whatever the text" do
    check all(text <- one_of([string(:printable), binary()]), max_runs: 500) do
      assert %OpenUI.Program{} = program = OpenUI.Parser.parse(text, Conformance.library())
      assert is_map(OpenUI.Canonical.result(program, Conformance.library()))
    end
  end

  property "streaming any split of a fixture equals parsing it at once" do
    check all(
            id <- member_of(Conformance.program_inputs_ids()),
            text = Conformance.input_text(id),
            cuts <- uniq_list_of(integer(0..byte_size(text)), max_length: 8)
          ) do
      chunks = split_at_bytes(text, Enum.sort(cuts))
      library = Conformance.library()

      streamed =
        chunks
        |> Enum.reduce(OpenUI.Stream.new(library), &OpenUI.Stream.push(&2, &1))
        |> OpenUI.Stream.finish()

      assert OpenUI.Canonical.result(OpenUI.Stream.program(streamed), library) ==
               OpenUI.Canonical.result(OpenUI.Parser.parse(text, library), library)
    end
  end

  property "every prefix of every fixture loads into the runtime and encodes as JSON" do
    check all(
            id <- member_of(Conformance.program_inputs_ids()),
            text = Conformance.input_text(id),
            size <- integer(0..byte_size(text))
          ) do
      library = Conformance.library()
      program = OpenUI.Parser.parse(binary_part(text, 0, size), library)
      {runtime, _effects} = library |> OpenUI.Runtime.new([]) |> OpenUI.Runtime.load(program)
      assert {_runtime, _effects} = OpenUI.Runtime.finish(runtime)
      assert is_binary(JSON.encode!(OpenUI.Canonical.result(program, library)["root"]))
    end
  end

  test "every prefix of the fixtures with multibyte text renders to JSON-encodable values" do
    library = Conformance.library()

    for id <- Conformance.program_inputs_ids(),
        text = Conformance.input_text(id),
        byte_size(text) != String.length(text),
        size <- 0..byte_size(text) do
      program = OpenUI.Parser.parse(binary_part(text, 0, size), library)

      assert is_binary(JSON.encode!(OpenUI.Canonical.result(program, library)["root"])),
             "#{id} at #{size}"
    end
  end

  defp split_at_bytes(text, cuts) do
    {chunks, last} =
      Enum.reduce(cuts, {[], 0}, fn cut, {chunks, from} ->
        {[binary_part(text, from, cut - from) | chunks], cut}
      end)

    Enum.reverse([binary_part(text, last, byte_size(text) - last) | chunks])
  end
end
