defmodule OpenUI.Parser do
  @moduledoc """
  Parses OpenUI Lang into an `OpenUI.Program` (language.md, sections 1, 2
  and 8).

  `parse/2` reads a complete response, which is the same as the end of a
  stream. It expects the program content: read a stored message with
  `OpenUI.Message.parse/2` first. Parsing never raises: a mistake in the
  program drops the smallest unit and is reported in `errors`, and a failure
  of the parser itself becomes a `parse-exception` error.
  """

  alias OpenUI.{Error, Library, Program, Statement}
  alias OpenUI.Parser.{Expression, Materializer, Source, Statements, Validator}
  alias OpenUI.Program.{Mutation, Query}

  @reserved_calls ["Query", "Mutation"]

  @doc "Parses a complete response."
  @spec parse(String.t(), Library.t() | module()) :: Program.t()
  def parse(text, library) when is_binary(text) do
    library = Library.resolve(library)
    prepared = Source.prepare(text)
    {texts, ""} = Statements.split(prepared, final: true)
    statements = texts |> Enum.map(&statement/1) |> Enum.reject(&is_nil/1)
    incomplete? = texts != [] and elem(Statements.auto_close(List.last(texts)), 1)

    cond do
      prepared == "" ->
        %Program{}

      statements == [] ->
        %Program{incomplete: incomplete?, errors: [parse_failed()]}

      true ->
        build(statements, library, final: true, incomplete: incomplete?)
    end
  rescue
    # language.md, section 8.2: a failure of the parser itself must be caught
    # and reported, never raised into the host.
    exception -> %Program{errors: [parse_exception(exception)]}
  end

  @doc """
  Reads one statement text, closing it first when it was cut off. Returns
  `nil` when the text is not a statement.
  """
  @spec statement(String.t()) :: Statement.t() | nil
  def statement(text) when is_binary(text) do
    {closed, cut_off?} = Statements.auto_close(text)

    case Expression.parse_statement(closed) do
      nil -> nil
      statement -> %{statement | pending?: cut_off?}
    end
  end

  @doc """
  Builds a program from statements. A later statement with a name already
  seen replaces it in place.

  Options:

    * `:final` (default `true`): the stream has ended, so `no-root` is
      reported and enum checks run;
    * `:incomplete` (default `false`): the text ended inside a string or a
      bracket;
    * `:ignore_state` (default `[]`): state names not to declare yet, such as
      a `$name` still growing at the end of a stream.
  """
  @spec build([Statement.t()], Library.t() | module(), keyword()) :: Program.t()
  def build(statements, library, opts \\ []) do
    library = Library.resolve(library)
    final? = Keyword.get(opts, :final, true)
    incomplete? = Keyword.get(opts, :incomplete, false)
    statements = last_definition_wins(statements)
    entry = pick_entry(statements, library.root)
    entry_id = entry && elem(entry, 0)
    symbols = Map.new(statements, &{&1.id, &1.ast})

    unreached =
      for %Statement{kind: :value, id: id} <- statements,
          id != entry_id,
          into: MapSet.new(),
          do: id

    ctx = Materializer.new(library, symbols, unreached, entry_id, incomplete? or not final?)
    {root, root_expression, ctx} = materialize_entry(entry, symbols, ctx)

    {state, queries, mutations, ctx} =
      extract(statements, Keyword.get(opts, :ignore_state, []), ctx)

    ctx =
      if final?,
        do: entry_errors(entry, root, root_expression, symbols, library.root, ctx),
        else: ctx

    %Program{
      root: root,
      root_expression: root_expression,
      statements: statements,
      state: state,
      queries: queries,
      mutations: mutations,
      errors: Enum.reverse(ctx.errors),
      unresolved: ctx.unresolved |> Enum.reverse() |> Enum.uniq(),
      orphans: if(entry, do: unreached_in_order(statements, ctx.unreached), else: []),
      incomplete: incomplete?
    }
  end

  defp last_definition_wins(statements) do
    latest = Map.new(statements, &{&1.id, &1})

    statements
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(&Map.fetch!(latest, &1.id))
  end

  # The entry is the `root` statement or, without one, the first value
  # statement that calls the library's root component.
  defp pick_entry(statements, root_component) do
    cond do
      Enum.any?(statements, &(&1.id == "root")) ->
        {"root", false}

      fallback = root_component && Enum.find(statements, &calls_component?(&1, root_component)) ->
        {fallback.id, true}

      true ->
        nil
    end
  end

  defp calls_component?(%Statement{kind: :value, ast: {:component, name, _args}}, name), do: true
  defp calls_component?(_statement, _name), do: false

  defp materialize_entry(nil, _symbols, ctx), do: {nil, nil, ctx}

  defp materialize_entry({entry_id, _fallback?}, symbols, ctx) do
    case Materializer.value(Map.fetch!(symbols, entry_id), ctx) do
      {%OpenUI.Element{} = element, ctx} ->
        {%{element | statement_id: entry_id}, nil, ctx}

      {ast, ctx} when is_tuple(ast) ->
        if contains_component?(ast), do: {nil, ast, ctx}, else: {nil, nil, ctx}

      {_value, ctx} ->
        {nil, nil, ctx}
    end
  end

  defp extract(statements, ignored_state, ctx) do
    {declared, queries, mutations, ctx} =
      Enum.reduce(statements, {[], [], [], ctx}, fn statement, acc ->
        extract_one(statement, acc)
      end)

    declared_names = MapSet.new(declared, &elem(&1, 0))

    auto_declared =
      statements
      |> Enum.flat_map(&state_refs(&1.ast))
      |> Enum.uniq()
      |> Enum.reject(&(MapSet.member?(declared_names, &1) or &1 in ignored_state))
      |> Enum.map(&{&1, nil})

    {Enum.reverse(declared) ++ auto_declared, Enum.reverse(queries), Enum.reverse(mutations), ctx}
  end

  defp extract_one(%Statement{kind: :state} = statement, {declared, queries, mutations, ctx}) do
    {default, ctx} =
      Materializer.in_statement(ctx, statement.id, &Materializer.value(statement.ast, &1))

    default = if match?(%OpenUI.Unknown{}, default), do: nil, else: default
    {[{statement.id, default} | declared], queries, mutations, ctx}
  end

  defp extract_one(%Statement{kind: :query} = statement, {declared, queries, mutations, ctx}) do
    {:component, "Query", raw_args} = statement.ast
    {[tool, args, defaults, refresh], ctx} = call_args(statement.id, raw_args, 4, ctx)

    query = %Query{
      id: statement.id,
      tool: tool,
      args: args,
      defaults: defaults,
      refresh: refresh,
      deps: raw_args |> Enum.at(1) |> state_refs() |> Enum.uniq()
    }

    {declared, [query | queries], mutations, ctx}
  end

  defp extract_one(%Statement{kind: :mutation} = statement, {declared, queries, mutations, ctx}) do
    {:component, "Mutation", raw_args} = statement.ast
    {[tool, args], ctx} = call_args(statement.id, raw_args, 2, ctx)
    {declared, queries, [%Mutation{id: statement.id, tool: tool, args: args} | mutations], ctx}
  end

  defp extract_one(%Statement{kind: :value}, acc), do: acc

  defp call_args(statement_id, raw_args, count, ctx) do
    Materializer.in_statement(ctx, statement_id, fn ctx ->
      raw_args
      |> Enum.concat(List.duplicate(nil, count))
      |> Enum.take(count)
      |> Enum.map_reduce(ctx, fn
        nil, ctx -> {nil, ctx}
        arg, ctx -> Materializer.expression(arg, ctx)
      end)
    end)
  end

  defp entry_errors(nil, _root, _expression, _symbols, root_component, ctx),
    do: Validator.issue(ctx, root_component || "", "", "no-root", reason: :missing)

  defp entry_errors({entry_id, fallback?}, root, expression, symbols, root_component, ctx) do
    ctx = %{ctx | statement_id: entry_id}

    cond do
      root == nil and expression == nil and
          not component_call?(Map.fetch!(symbols, entry_id), symbols) ->
        Validator.issue(ctx, root_component || "", "", "no-root", reason: :not_component)

      fallback? and root != nil ->
        Validator.issue(ctx, root_component, "", "no-root", reason: :fallback, severity: :warning)

      fallback? ->
        Validator.issue(ctx, root_component, "", "no-root", reason: :missing)

      true ->
        ctx
    end
  end

  # Follows references to the entry's value: a component call that did not
  # render was dropped by validation, which reported it already.
  defp component_call?(ast, symbols, seen \\ MapSet.new())

  defp component_call?({:ref, name}, symbols, seen) do
    if MapSet.member?(seen, name) or not Map.has_key?(symbols, name),
      do: false,
      else: component_call?(Map.fetch!(symbols, name), symbols, MapSet.put(seen, name))
  end

  defp component_call?({:component, name, _args}, _symbols, _seen),
    do: name not in @reserved_calls

  defp component_call?(_ast, _symbols, _seen), do: false

  defp contains_component?({:component, name, _args}) when name not in @reserved_calls, do: true

  defp contains_component?(ast) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.any?(&contains_component?/1)

  defp contains_component?(list) when is_list(list), do: Enum.any?(list, &contains_component?/1)
  defp contains_component?(_other), do: false

  defp state_refs({:state, name}), do: [name]

  defp state_refs(ast) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.flat_map(&state_refs/1)

  defp state_refs(list) when is_list(list), do: Enum.flat_map(list, &state_refs/1)
  defp state_refs(_other), do: []

  defp unreached_in_order(statements, unreached),
    do: for(%Statement{id: id} <- statements, MapSet.member?(unreached, id), do: id)

  defp parse_failed do
    %Error{
      source: :parser,
      code: "parse-failed",
      message: "The response has text but no statements of the form name = expression"
    }
  end

  defp parse_exception(exception) do
    %Error{
      source: :parser,
      code: "parse-exception",
      message: "The parser failed: " <> Exception.message(exception)
    }
  end
end
