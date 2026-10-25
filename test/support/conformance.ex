defmodule OpenUI.Conformance do
  @moduledoc false

  alias OpenUI.Runtime.Validation

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

  @optional_keys ["state", "statements", "errorObjects"]

  def case_ids, do: program_case_ids() ++ interaction_case_ids()

  def interaction_case_ids do
    for id <- program_case_ids(),
        File.exists?(Path.join([@root, id, "interactions.json"])),
        do: id <> "+interactions"
  end

  @doc "Cases whose program text is in input.oui or chunks.json."
  def program_inputs_ids do
    for id <- program_case_ids(),
        files = files(id),
        Map.has_key?(files, "input.oui") or Map.has_key?(files, "chunks.json"),
        do: id
  end

  @doc "The program text of a case, with chunks joined."
  def input_text(id) do
    case files(id) do
      %{"input.oui" => input} -> input
      %{"chunks.json" => chunks} -> chunks |> JSON.decode!() |> Enum.join()
    end
  end

  @doc "The key of the first element in the tree that came from `statement_id`."
  def key_of(nil, _statement_id), do: nil
  def key_of(%OpenUI.Element{statement_id: statement_id, key: key}, statement_id), do: key

  def key_of(%OpenUI.Element{props: props}, statement_id),
    do: key_of(Map.values(props), statement_id)

  def key_of(list, statement_id) when is_list(list),
    do: Enum.find_value(list, &key_of(&1, statement_id))

  def key_of(map, statement_id) when is_map(map) and not is_struct(map),
    do: key_of(Map.values(map), statement_id)

  def key_of(_value, _statement_id), do: nil

  @doc "Runs one case; returns the list of differences, empty when it passes."
  def run(id) do
    case String.split(id, "+") do
      [case_id, "interactions"] -> run_interactions(case_id)
      [case_id] -> case_id |> files() |> run_case(case_id)
    end
  end

  @fields %{"Input" => [name: "name", type: "input"]}
  @forms %{"Form" => "name"}

  # A host that runs effects on the spot: tool interactions set what a tool
  # returns from then on, and the ones before the first user interaction
  # apply before the program mounts.
  defp run_interactions(id) do
    files = files(id)
    %{"interactions" => steps, "expected" => expected} = JSON.decode!(files["interactions.json"])
    {setup, steps} = Enum.split_while(steps, &Map.has_key?(&1, "tool"))
    host = %{tools: Map.new(setup, &{&1["tool"], &1["result"]}), events: [], calls: []}

    runtime = OpenUI.Runtime.new(library(), fields: @fields, forms: @forms)

    {runtime, effects} =
      OpenUI.Runtime.load(runtime, OpenUI.Parser.parse(files["input.oui"], library()))

    {runtime, host} = run_effects(runtime, effects, host)
    {runtime, effects} = OpenUI.Runtime.finish(runtime)
    {runtime, host} = run_effects(runtime, effects, host)
    {runtime, host} = Enum.reduce(steps, {runtime, host}, &interact/2)

    events_diff(expected, Enum.reverse(host.events)) ++
      state_diff(expected, OpenUI.Runtime.state(runtime)) ++
      tool_calls_diff(expected, host.calls |> Enum.reverse() |> Enum.dedup())
  end

  defp interact(%{"tool" => tool, "result" => result}, {runtime, host}),
    do: {runtime, put_in(host.tools[tool], result)}

  defp interact(%{"type" => [statement_id, text]}, {runtime, host}) do
    {runtime, effects} =
      OpenUI.Runtime.input(runtime, key_of(OpenUI.Runtime.tree(runtime), statement_id), text)

    run_effects(runtime, effects, host)
  end

  defp interact(%{"click" => statement_id}, {runtime, host}) do
    {runtime, effects} =
      OpenUI.Runtime.trigger(
        runtime,
        key_of(OpenUI.Runtime.tree(runtime), statement_id),
        "action"
      )

    run_effects(runtime, effects, host)
  end

  defp run_effects(runtime, effects, host),
    do: Enum.reduce(effects, {runtime, host}, &run_effect/2)

  defp run_effect({:emit, event}, {runtime, host}),
    do: {runtime, %{host | events: [event | host.events]}}

  defp run_effect({:run_query, query_id, tool, args}, {runtime, host}) do
    {result, host} = call_tool(host, tool, args)
    {runtime, effects} = OpenUI.Runtime.query_result(runtime, query_id, args, result)
    run_effects(runtime, effects, host)
  end

  defp run_effect({:run_mutation, run_ref, tool, args}, {runtime, host}) do
    {result, host} = call_tool(host, tool, args)
    {runtime, effects} = OpenUI.Runtime.mutation_result(runtime, run_ref, result)
    run_effects(runtime, effects, host)
  end

  defp run_effect({:schedule_refresh, _query_id, _seconds}, acc), do: acc

  defp call_tool(host, tool, args) do
    case Map.fetch(host.tools, tool) do
      {:ok, result} ->
        {{:ok, result}, %{host | calls: [%{"tool" => tool, "args" => args} | host.calls]}}

      :error ->
        {{:error, {:tool_not_found, Map.keys(host.tools)}}, host}
    end
  end

  defp events_diff(expected, events) do
    wanted = Map.get(expected, "events", [])
    got = Enum.map(events, &OpenUI.Event.to_map/1)

    ok? =
      length(wanted) == length(got) and
        Enum.all?(Enum.zip(wanted, got), fn {want, event} ->
          Enum.all?(want, fn {key, value} -> Map.get(event, key) == value end)
        end)

    if ok?, do: [], else: ["events: expected #{inspect(wanted)}, got #{inspect(got)}"]
  end

  defp state_diff(expected, state) do
    for {key, value} <- Map.get(expected, "state", %{}), Map.get(state, key) != value do
      "state #{key}: expected #{inspect(value)}, got #{inspect(Map.get(state, key))}"
    end
  end

  defp tool_calls_diff(%{"toolCalls" => wanted}, calls) when wanted != calls,
    do: ["toolCalls: expected #{inspect(wanted)}, got #{inspect(calls)}"]

  defp tool_calls_diff(_expected, _calls), do: []

  defp run_case(%{"validation.json" => validation}, _id) do
    for {%{"rules" => rules, "value" => value, "valid" => valid?}, index} <-
          validation |> JSON.decode!() |> Map.fetch!("cases") |> Enum.with_index(),
        result = Validation.validate(value, rules),
        result == :ok != valid? do
      "case #{index} #{inspect(rules)} #{inspect(value)}: got #{inspect(result)}"
    end
  end

  defp run_case(%{"chunks.json" => chunks} = files, _id) do
    expected = JSON.decode!(files["expected.json"])
    chunks = JSON.decode!(chunks)

    streamed =
      chunks
      |> Enum.reduce(OpenUI.Stream.new(library()), &OpenUI.Stream.push(&2, &1))
      |> OpenUI.Stream.finish()
      |> OpenUI.Stream.program()

    batch = OpenUI.Parser.parse(Enum.join(chunks), library())

    Enum.map(diff(expected, OpenUI.Canonical.result(streamed, library())), &("streamed " <> &1)) ++
      Enum.map(diff(expected, OpenUI.Canonical.result(batch, library())), &("batch " <> &1))
  end

  defp run_case(%{"patch.oui" => patch, "input.oui" => input} = files, _id) do
    expected = JSON.decode!(files["expected.json"])
    merged = OpenUI.Edit.merge(input, patch)

    statements =
      merged
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case Regex.run(~r/^(\$?\w+)\s*=(?!=)/, line) do
          [_line, name] -> [name]
          nil -> []
        end
      end)

    actual =
      OpenUI.Parser.parse(merged, library())
      |> OpenUI.Canonical.result(library())
      |> Map.put("statements", statements)

    diff(expected, actual)
  end

  defp run_case(%{"input.oui" => input, "expected.json" => expected}, id) do
    expected = JSON.decode!(expected)
    program = OpenUI.Parser.parse(input, library())

    diff(expected, OpenUI.Canonical.result(program, library())) ++
      roundtrip(id, expected, program)
  end

  # *-roundtrip-* cases also serialize the rendered tree and parse it again.
  defp roundtrip(id, expected, program) do
    with true <- String.contains?(id, "-roundtrip-"),
         %OpenUI.Element{} = tree <- OpenUI.Canonical.tree(program, library()) do
      text = OpenUI.Serializer.to_source(tree, library(), state: %{})
      again = OpenUI.Canonical.result(OpenUI.Parser.parse(text, library()), library())["root"]

      if again == expected["root"],
        do: [],
        else: ["roundtrip: #{inspect(text)} parses to #{inspect(again)}"]
    else
      _not_a_roundtrip_case -> []
    end
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
