defmodule OpenUI.Conformance do
  @moduledoc false

  @root Path.expand("../fixtures/openui-spec", __DIR__)

  def root, do: @root

  def program_case_ids do
    @root
    |> Path.join("*/*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, @root))
    |> Enum.sort()
  end

  @pending_file Path.expand("conformance_pending.txt", __DIR__)
  @external_resource @pending_file
  @pending (if File.exists?(@pending_file) do
              @pending_file |> File.read!() |> String.split("\n", trim: true) |> MapSet.new()
            else
              MapSet.new()
            end)

  @optional_keys ["state", "statements", "errorObjects"]

  def case_ids, do: program_case_ids()

  def pending?(id), do: MapSet.member?(@pending, id)

  @doc "Runs one case; returns the list of differences, empty when it passes."
  def run(id) do
    files = files(id)
    expected = JSON.decode!(files["expected.json"])

    actual =
      OpenUI.Canonical.result(OpenUI.Parser.parse(files["input.oui"], library()), library())

    diff(expected, actual)
  end

  def diff(expected, actual) do
    for {key, compare} <- comparisons(),
        Map.has_key?(expected, key) or key not in @optional_keys,
        not compare.(expected[key], actual[key]) do
      "#{key}: expected #{inspect(expected[key])}, got #{inspect(actual[key])}"
    end
  end

  defp comparisons do
    [
      {"root", &==/2},
      {"errors", fn want, got -> length(want) == length(got) and claims?(want, got) end},
      {"unresolved", &same_set?/2},
      {"orphans", &same_set?/2},
      {"incomplete", &==/2},
      {"state", &==/2},
      {"statements", &==/2},
      {"errorObjects", &claims?/2}
    ]
  end

  defp same_set?(want, got), do: Enum.sort(Enum.uniq(want)) == Enum.sort(Enum.uniq(got))

  # Each expected entry claims its own actual entry that agrees on the keys it
  # lists, so an error without statementId matches any statement.
  defp claims?(expected, actual) do
    expected
    |> Enum.sort_by(&(-map_size(&1)))
    |> Enum.reduce_while(actual, fn entry, pool ->
      case Enum.find_index(pool, &agrees?(entry, &1)) do
        nil -> {:halt, :unclaimed}
        index -> {:cont, List.delete_at(pool, index)}
      end
    end)
    |> Kernel.!=(:unclaimed)
  end

  defp agrees?(entry, candidate),
    do: Enum.all?(entry, fn {key, value} -> Map.get(candidate, key) == value end)

  def library do
    {:ok, library} =
      OpenUI.Library.from_spec(File.read!(Path.join(@root, "library.json")),
        functions: %{"Upper" => fn %{"text" => text} -> String.upcase(text) end}
      )

    library
  end

  def files(id) do
    dir = Path.join(@root, id)

    dir
    |> File.ls!()
    |> Map.new(&{&1, File.read!(Path.join(dir, &1))})
  end
end
