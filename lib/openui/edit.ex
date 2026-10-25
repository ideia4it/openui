defmodule OpenUI.Edit do
  @moduledoc """
  Incremental editing (language.md, section 7): merges a patch, the changed
  statements a model answers with in edit mode, into the current program.

  Both texts are read with the parser's own rules for fences, comments and
  statement boundaries, so a multi-line ternary is one statement in both. A
  patch statement replaces the one with its name in place; a new name is
  appended; `name = null` deletes the statement. After merging, statements
  `root` cannot reach are removed, unless there is no `root` statement.
  State declarations are always kept. Merge only once the patch has finished
  streaming: a half-written `root` would remove statements it reaches later.
  """

  alias OpenUI.Parser
  alias OpenUI.Parser.{Source, Statements}

  @doc "Merges `patch` into the `current` program text and returns the merged text."
  @spec merge(String.t(), String.t()) :: String.t()
  def merge(current, patch) when is_binary(current) and is_binary(patch) do
    case {statements(current), statements(patch)} do
      {[], patch_statements} ->
        Enum.map_join(patch_statements, "\n", & &1.text)

      {_current_statements, []} ->
        current

      {current_statements, patch_statements} ->
        merge_statements(current_statements, patch_statements)
    end
  end

  defp statements(text) do
    {texts, ""} = text |> Source.prepare() |> Statements.split(final: true)

    for text <- texts, statement = Parser.statement(text), statement != nil do
      %{id: statement.id, ast: statement.ast, text: text}
    end
  end

  defp merge_statements(current, patch) do
    merged =
      Enum.reduce(current ++ patch, [], fn statement, merged ->
        cond do
          statement in patch and statement.ast == :null ->
            List.keydelete(merged, statement.id, 0)

          List.keymember?(merged, statement.id, 0) ->
            List.keyreplace(merged, statement.id, 0, {statement.id, statement})

          true ->
            merged ++ [{statement.id, statement}]
        end
      end)

    merged
    |> remove_unreachable()
    |> Enum.map_join("\n", fn {_id, statement} -> statement.text end)
  end

  defp remove_unreachable(merged) do
    if List.keymember?(merged, "root", 0) do
      by_id = Map.new(merged)
      reachable = reach(["root"], by_id, MapSet.new(["root"]))

      Enum.filter(merged, fn {id, _statement} ->
        MapSet.member?(reachable, id) or String.starts_with?(id, "$")
      end)
    else
      merged
    end
  end

  defp reach([], _by_id, reachable), do: reachable

  defp reach([id | queue], by_id, reachable) do
    new_refs =
      by_id
      |> Map.fetch!(id)
      |> Map.fetch!(:ast)
      |> refs()
      |> Enum.filter(&(Map.has_key?(by_id, &1) and not MapSet.member?(reachable, &1)))
      |> Enum.uniq()

    reach(queue ++ new_refs, by_id, Enum.into(new_refs, reachable))
  end

  defp refs({:ref, name}), do: [name]
  defp refs(ast) when is_tuple(ast), do: ast |> Tuple.to_list() |> Enum.flat_map(&refs/1)
  defp refs(list) when is_list(list), do: Enum.flat_map(list, &refs/1)
  defp refs(_other), do: []
end
