defmodule OpenUI.Runtime do
  @moduledoc """
  A rendered program as a pure value: its state store, form fields, query
  results and mutations, with the interactions of language.md, sections 5
  and 6.

  Functions that may cause something outside the program to happen return
  `{runtime, effects}`. The host runs the effects and reports back:

    * `{:emit, %OpenUI.Event{}}`: an action for the host or the model;
    * `{:run_query, query_id, tool, args}`: call the tool, then
      `query_result/4`;
    * `{:run_mutation, run_ref, tool, args}`: call the tool, then
      `mutation_result/3`;
    * `{:schedule_refresh, query_id, seconds}`: call `refresh/2` later. A new one for
      the same query replaces the pending one: keep one timer per query.

  Which components are fields and which give a form name to their subtree is
  up to each platform (prompt.md, section 2.6), so the runtime takes it as
  options:

      OpenUI.Runtime.new(MyApp.Library,
        fields: %{"Input" => [name: "name", type: "input"]},
        forms: %{"Form" => "name"}
      )

  A field option may add `rules: "rules"`, the prop holding its validation
  rules (`"rules"` by default).
  """

  alias OpenUI.{ActionPlan, Binding, Element, Error, Event, Library, Program}
  alias OpenUI.Runtime.{Context, Evaluator, HostValue, Validation, Value}

  @derive {Inspect, only: [:finished?, :store, :field_errors]}
  defstruct [
    :library,
    program: %Program{},
    store: %{},
    pristine: MapSet.new(),
    fields: %{},
    forms: %{},
    finished?: false,
    query_timing: :on_finish,
    tree: nil,
    elements: %{},
    render_errors: [],
    field_errors: %{},
    queries: %{},
    mutations: %{},
    runs: %{},
    emitted_errors: []
  ]

  @type effect ::
          {:emit, Event.t()}
          | {:run_query, String.t(), String.t(), map()}
          | {:run_mutation, reference(), String.t(), map()}
          | {:schedule_refresh, String.t(), number()}

  @type t :: %__MODULE__{}

  @doc """
  Starts a runtime. Options: `:fields`, `:forms`, `:state`, the state a
  host persisted earlier, applied over the program's defaults, and
  `:queries`, when queries run: `:on_finish` (default) once the stream ends,
  or `:on_statement` as soon as the statement holding each one and every
  statement it reads are complete, for hosts that answer queries from results
  they already hold.
  """
  @spec new(Library.t() | module(), keyword()) :: t()
  def new(library, opts \\ []) do
    %__MODULE__{
      library: Library.resolve(library),
      fields: Map.new(Keyword.get(opts, :fields, %{})),
      forms: Map.new(Keyword.get(opts, :forms, %{})),
      store: Map.new(Keyword.get(opts, :state, %{})),
      query_timing: Keyword.get(opts, :queries, :on_finish)
    }
    |> render()
  end

  @doc """
  Loads a program, from a stream frame or an edit. Declared defaults apply to
  state the person has not changed; no key is ever deleted. Queries run at
  `finish/1`, or here once their statement and every statement they read are
  complete when the runtime was started with `queries: :on_statement`.
  """
  @spec load(t(), Program.t()) :: {t(), [effect()]}
  def load(%__MODULE__{} = runtime, %Program{} = program) do
    runtime = %{runtime | program: program} |> apply_defaults() |> render()

    cond do
      runtime.finished? -> sync_queries(runtime)
      runtime.query_timing == :on_statement -> sync_queries(runtime, settled_queries(program))
      true -> {runtime, []}
    end
  end

  @doc """
  Starts over for a new response in the same place: a new stream, the given
  persisted state, no queries or mutations. The errors already reported are
  kept, so `take_errors/2` clears them with `[]` (language.md, section 8.3).
  """
  @spec restart(t(), map()) :: t()
  def restart(%__MODULE__{} = runtime, state \\ %{}) do
    render(%{
      runtime
      | program: %Program{},
        store: state,
        pristine: MapSet.new(),
        finished?: false,
        field_errors: %{},
        queries: %{},
        mutations: %{},
        runs: %{}
    })
  end

  @doc "Marks the end of the stream: every query runs."
  @spec finish(t()) :: {t(), [effect()]}
  def finish(%__MODULE__{} = runtime), do: sync_queries(%{runtime | finished?: true})

  @doc """
  The tool answered a query. A result for arguments that are no longer the
  query's current ones is discarded. `{:error, {:tool_not_found, names}}`
  reports `tool-not-found` with the available names; any other error
  reports `tool-error`. Either way the query keeps its last good data.
  """
  @spec query_result(t(), String.t(), map(), {:ok, term()} | {:error, term()}) ::
          {t(), [effect()]}
  def query_result(%__MODULE__{} = runtime, query_id, args, result) do
    case Map.fetch(runtime.queries, query_id) do
      {:ok, %{args: ^args} = entry} ->
        entry = settle_query(entry, query_id, result)
        runtime = render(%{runtime | queries: Map.put(runtime.queries, query_id, entry)})
        {runtime, refresh_effects(query_id, entry)}

      _stale_or_unknown ->
        {runtime, []}
    end
  end

  @doc "Fetches a query again, as its refresh interval asks."
  @spec refresh(t(), String.t()) :: {t(), [effect()]}
  def refresh(%__MODULE__{} = runtime, query_id) do
    case Enum.find(runtime.program.queries, &(&1.id == query_id)) do
      nil -> {runtime, []}
      query -> fetch(runtime, query)
    end
  end

  @doc """
  The tool answered a mutation started by `{:run_mutation, run_ref, ...}`.
  On success the rest of its action plan runs; on failure it stops.
  """
  @spec mutation_result(t(), reference(), {:ok, term()} | {:error, term()}) :: {t(), [effect()]}
  def mutation_result(%__MODULE__{} = runtime, run_ref, result) do
    case Map.pop(runtime.runs, run_ref) do
      {nil, _runs} -> {runtime, []}
      {run, runs} -> settle_mutation(%{runtime | runs: runs}, run, result)
    end
  end

  @doc "Fetch state of the queries, for a loading indicator and error display."
  @spec query_status(t()) :: %{loading?: boolean(), refetching?: boolean(), errors: [Error.t()]}
  def query_status(%__MODULE__{queries: queries}) do
    entries = Map.values(queries)

    %{
      loading?: Enum.any?(entries, & &1.loading?),
      refetching?: Enum.any?(entries, & &1.refetching?),
      errors: for(%{error: %Error{} = error} <- entries, do: error)
    }
  end

  @doc """
  The error list to send to the host, only when it changed since the last
  call (language.md, section 8.3). While a stream is open nothing is
  reported, and a list left from an earlier stream is cleared with `[]`.
  `renderer_errors` are errors the host's renderer adds, such as a component
  that raised.
  """
  @spec take_errors(t(), [Error.t()]) :: {t(), :unchanged | {:changed, [Error.t()]}}
  def take_errors(runtime, renderer_errors \\ [])

  def take_errors(%__MODULE__{finished?: false, emitted_errors: []} = runtime, _renderer_errors),
    do: {runtime, :unchanged}

  def take_errors(%__MODULE__{finished?: false} = runtime, _renderer_errors),
    do: {%{runtime | emitted_errors: []}, {:changed, []}}

  def take_errors(%__MODULE__{} = runtime, renderer_errors) do
    current = current_errors(runtime) ++ renderer_errors

    if current == runtime.emitted_errors,
      do: {runtime, :unchanged},
      else: {%{runtime | emitted_errors: current}, {:changed, current}}
  end

  @doc "The evaluated tree, with a `key` on every element."
  @spec tree(t()) :: Element.t() | nil
  def tree(%__MODULE__{tree: tree}), do: tree

  @doc """
  The state store: `$variables` with their values, form names with their
  fields, page-level fields at the top, each field as `%{"value",
  "componentType"}`. This is what a host persists.
  """
  @spec state(t()) :: map()
  def state(%__MODULE__{store: store}), do: store

  @doc "The errors the latest evaluation reported."
  @spec render_errors(t()) :: [OpenUI.Error.t()]
  def render_errors(%__MODULE__{render_errors: errors}), do: errors

  @doc "The rule a field failed at the latest submit, or `nil`."
  @spec field_error(t(), String.t()) :: String.t() | nil
  def field_error(%__MODULE__{field_errors: errors}, key), do: Map.get(errors, key)

  @doc "The name of the nearest form around an element, or `nil`."
  @spec form_name(t(), String.t()) :: String.t() | nil
  def form_name(%__MODULE__{} = runtime, key) do
    runtime.elements
    |> Enum.filter(fn {ancestor_key, element} ->
      String.starts_with?(key, ancestor_key <> ".") and Map.has_key?(runtime.forms, element.type)
    end)
    |> Enum.max_by(fn {ancestor_key, _element} -> byte_size(ancestor_key) end, fn -> nil end)
    |> case do
      nil -> nil
      {_key, form} -> form.props[runtime.forms[form.type]]
    end
  end

  @doc """
  The person changed a field. A bound prop writes its `$variable`; a field
  without a binding writes into its form, or the page when it has none.
  """
  @spec input(t(), String.t(), term()) :: {t(), [effect()]}
  def input(%__MODULE__{} = runtime, key, value) do
    case Map.fetch(runtime.elements, key) do
      {:ok, element} -> runtime |> write_field(key, element, value) |> refetch_changed_deps()
      :error -> {runtime, []}
    end
  end

  @doc """
  Runs the action plan in a prop of an element. Inside a form, a plan that
  sends something (`@ToAssistant`, a library action or a mutation) runs only
  when every field of the form passes its rules.
  """
  @spec trigger(t(), String.t(), String.t()) :: {t(), [effect()]}
  def trigger(%__MODULE__{} = runtime, key, prop) do
    with {:ok, element} <- Map.fetch(runtime.elements, key),
         %ActionPlan{steps: steps} <- element.props[prop] do
      form = form_name(runtime, key)

      case validate_form(runtime, form, steps) do
        {:ok, runtime} -> run_steps(runtime, steps, form, [])
        {:invalid, runtime} -> {runtime, []}
      end
    else
      _no_plan -> {runtime, []}
    end
  end

  defp apply_defaults(runtime) do
    ctx = %Context{library: runtime.library}

    Enum.reduce(runtime.program.state, runtime, fn {name, default}, runtime ->
      if Map.has_key?(runtime.store, name) and not MapSet.member?(runtime.pristine, name) do
        runtime
      else
        %{
          runtime
          | store: Map.put(runtime.store, name, Evaluator.evaluate(default, ctx)),
            pristine: MapSet.put(runtime.pristine, name)
        }
      end
    end)
  end

  defp render(runtime) do
    {tree, errors} = Evaluator.evaluate_root(runtime.program, context(runtime))
    %{runtime | tree: tree, elements: index_elements(tree), render_errors: errors}
  end

  defp context(runtime) do
    %Context{
      library: runtime.library,
      state: plain_state(runtime),
      queries: Map.new(runtime.program.queries, &{&1.id, query_value(runtime, &1)}),
      mutations: Map.new(runtime.mutations, fn {id, mutation} -> {id, mutation.result} end)
    }
  end

  defp plain_state(runtime),
    do: Map.new(runtime.store, fn {name, value} -> {name, unwrap(value)} end)

  # References resolve to the latest result, or to the defaults before the first one.
  defp query_value(runtime, query) do
    case Map.get(runtime.queries, query.id) do
      %{fetched?: true, data: data} -> data
      _not_fetched -> Evaluator.evaluate(query.defaults, %Context{library: runtime.library})
    end
  end

  defp unwrap(%{"value" => value, "componentType" => _type}), do: value
  defp unwrap(value), do: value

  defp index_elements(nil), do: %{}
  defp index_elements(tree), do: tree |> collect_elements([]) |> Map.new()

  defp collect_elements(%Element{} = element, acc),
    do:
      Enum.reduce(element.props, [{element.key, element} | acc], fn {_name, value}, acc ->
        collect_elements(value, acc)
      end)

  defp collect_elements(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &collect_elements/2)

  defp collect_elements(map, acc) when is_map(map) and not is_struct(map),
    do: Enum.reduce(map, acc, fn {_key, value}, acc -> collect_elements(value, acc) end)

  defp collect_elements(_value, acc), do: acc

  defp write_field(runtime, key, element, value) do
    runtime =
      case bound_state(element) do
        %Binding{name: name} -> set_state(runtime, name, value)
        nil -> write_form_field(runtime, key, element, value)
      end

    runtime
    |> render()
    |> recheck_field(key)
  end

  defp bound_state(element),
    do:
      Enum.find_value(element.props, fn {_name, value} -> match?(%Binding{}, value) && value end)

  defp write_form_field(runtime, key, element, value) do
    case Map.fetch(runtime.fields, element.type) do
      {:ok, config} ->
        field = %{"value" => value, "componentType" => Keyword.fetch!(config, :type)}
        name = element.props[Keyword.fetch!(config, :name)]

        case form_name(runtime, key) do
          nil -> put_store(runtime, name, field)
          form -> put_store(runtime, form, Map.put(form_fields(runtime, form), name, field))
        end

      :error ->
        runtime
    end
  end

  defp form_fields(runtime, form) do
    case Map.get(runtime.store, form) do
      fields when is_map(fields) -> fields
      _other -> %{}
    end
  end

  defp set_state(runtime, name, value), do: put_store(runtime, name, value)

  defp put_store(runtime, name, value),
    do: %{
      runtime
      | store: Map.put(runtime.store, name, value),
        pristine: MapSet.delete(runtime.pristine, name)
    }

  # A field that failed a submit is checked again as the person fixes it.
  defp recheck_field(runtime, key) do
    if Map.has_key?(runtime.field_errors, key) do
      case field_check(runtime, key, runtime.elements[key]) do
        :ok -> %{runtime | field_errors: Map.delete(runtime.field_errors, key)}
        {:error, rule} -> %{runtime | field_errors: Map.put(runtime.field_errors, key, rule)}
      end
    else
      runtime
    end
  end

  defp validate_form(runtime, nil, _steps), do: {:ok, runtime}

  defp validate_form(runtime, form, steps) do
    if Enum.any?(steps, &sends?/1) do
      errors =
        for {key, element} <- runtime.elements,
            Map.has_key?(runtime.fields, element.type),
            form_name(runtime, key) == form,
            {:error, rule} <- [field_check(runtime, key, element)],
            into: %{},
            do: {key, rule}

      runtime = %{runtime | field_errors: errors}
      if errors == %{}, do: {:ok, runtime}, else: {:invalid, runtime}
    else
      {:ok, runtime}
    end
  end

  defp sends?({:to_assistant, _message, _context}), do: true
  defp sends?({:custom, _name, _params}), do: true
  defp sends?({:run, _id, :mutation}), do: true
  defp sends?(_step), do: false

  defp field_check(runtime, key, element) do
    config = Map.get(runtime.fields, element.type, [])

    case element.props[Keyword.get(config, :rules, "rules")] do
      rules when is_map(rules) -> Validation.validate(field_value(runtime, key, element), rules)
      _no_rules -> :ok
    end
  end

  @doc """
  The current value of a field element: its bound `$variable`, or its entry
  in the form or page state.
  """
  @spec field_value(t(), String.t()) :: term()
  def field_value(%__MODULE__{} = runtime, key) do
    case Map.fetch(runtime.elements, key) do
      {:ok, element} -> field_value(runtime, key, element)
      :error -> nil
    end
  end

  defp field_value(runtime, key, element) do
    case bound_state(element) do
      %Binding{name: name} ->
        runtime.store |> Map.get(name) |> unwrap()

      nil ->
        name =
          element.props[runtime.fields |> Map.get(element.type, []) |> Keyword.get(:name, "name")]

        fields =
          if form = form_name(runtime, key), do: form_fields(runtime, form), else: runtime.store

        fields |> Map.get(name) |> unwrap()
    end
  end

  defp run_steps(runtime, [], _form, effects), do: {runtime, Enum.reverse(effects)}

  # A mutation run is awaited: the steps after it wait for mutation_result/3.
  defp run_steps(runtime, [{:run, id, :mutation} | rest], form, effects) do
    {runtime, mutation_effects} = start_mutation(runtime, id, rest, form)
    {runtime, Enum.reverse(effects, mutation_effects)}
  end

  defp run_steps(runtime, [step | rest], form, effects) do
    {runtime, step_effects} = run_step(runtime, step, form)
    run_steps(runtime, rest, form, Enum.reverse(step_effects, effects))
  end

  defp run_step(runtime, {:set, name, value}, _form) do
    value = Evaluator.evaluate(value, context(runtime))
    runtime |> set_state(name, value) |> render() |> refetch_changed_deps()
  end

  defp run_step(runtime, {:reset, targets}, _form) do
    defaults = Map.new(runtime.program.state)
    ctx = %Context{library: runtime.library}

    runtime =
      Enum.reduce(targets, runtime, fn target, runtime ->
        value = Evaluator.evaluate(Map.get(defaults, target), ctx)

        %{
          runtime
          | store: Map.put(runtime.store, target, value),
            pristine: MapSet.put(runtime.pristine, target)
        }
      end)

    runtime |> render() |> refetch_changed_deps()
  end

  defp run_step(runtime, {:to_assistant, message, context}, form) do
    params = if context == nil, do: %{}, else: %{"context" => context}
    {runtime, [{:emit, event(runtime, "continue_conversation", message, params, form)}]}
  end

  defp run_step(runtime, {:open_url, url}, form),
    do: {runtime, [{:emit, event(runtime, "open_url", "", %{"url" => url}, form)}]}

  defp run_step(runtime, {:custom, name, params}, form),
    do: {runtime, [{:emit, event(runtime, name, "", params, form)}]}

  defp run_step(runtime, {:run, id, :query}, _form) do
    case Enum.find(runtime.program.queries, &(&1.id == id)) do
      nil -> {runtime, []}
      query -> fetch(runtime, query)
    end
  end

  defp event(runtime, type, message, params, form) do
    %Event{
      type: type,
      human_friendly_message: message,
      params: params,
      form_name: form,
      form_state: form_state(runtime, form)
    }
  end

  defp form_state(runtime, nil), do: runtime.store
  defp form_state(runtime, form), do: %{form => form_fields(runtime, form)}

  # Queries run once the stream ends (or as they settle, with eager timing), and
  # again on load when an edit changed their tool or arguments.
  defp sync_queries(runtime), do: sync_queries(runtime, runtime.program.queries)

  defp sync_queries(runtime, queries) do
    ctx = context(runtime)
    changed = Enum.reject(queries, &same_request?(runtime, &1, ctx))
    fetch_all(runtime, changed)
  end

  # The stream closes a cut statement so it parses, and a name declared later
  # reads as null: either would send the tool a half-written request, one per
  # chunk. A query asks for its tool once its statement and every statement it
  # reads, directly or through others, is complete.
  defp settled_queries(program) do
    statements = Map.new(program.statements, &{&1.id, &1})
    Enum.filter(program.queries, &settled?(statements, &1.id, %{}))
  end

  defp settled?(statements, id, seen) do
    case Map.fetch(statements, id) do
      {:ok, %{pending?: false, ast: ast}} ->
        seen = Map.put(seen, id, true)

        ast
        |> read_names()
        |> Enum.reject(&Map.has_key?(seen, &1))
        |> Enum.all?(&settled?(statements, &1, seen))

      _pending_or_not_declared_yet ->
        false
    end
  end

  defp read_names({kind, name}) when kind in [:ref, :state] and is_binary(name), do: [name]
  defp read_names(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> read_names()
  defp read_names(list) when is_list(list), do: Enum.flat_map(list, &read_names/1)
  defp read_names(_value), do: []

  defp same_request?(runtime, query, ctx) do
    {tool, args} = request(query, ctx)
    match?(%{tool: ^tool, args: ^args}, Map.get(runtime.queries, query.id))
  end

  # A query fetches again when a $variable written literally in its args
  # changes; state reached through a referenced statement does not count.
  defp refetch_changed_deps(%{finished?: false} = runtime), do: {runtime, []}

  defp refetch_changed_deps(runtime) do
    state = plain_state(runtime)
    changed = Enum.filter(runtime.program.queries, &deps_changed?(runtime, &1, state))
    fetch_all(runtime, changed)
  end

  # Once the stream ends every query has been fetched, so each has an entry.
  defp deps_changed?(runtime, query, state),
    do: Map.take(state, query.deps) != Map.fetch!(runtime.queries, query.id).deps

  defp fetch_all(runtime, queries) do
    Enum.reduce(queries, {runtime, []}, fn query, {runtime, effects} ->
      {runtime, more} = fetch(runtime, query)
      {runtime, effects ++ more}
    end)
  end

  defp fetch(runtime, query) do
    ctx = context(runtime)
    {tool, args} = request(query, ctx)
    previous = Map.get(runtime.queries, query.id, %{fetched?: false, data: nil, error: nil})

    entry = %{
      tool: tool,
      args: args,
      deps: Map.take(ctx.state, query.deps),
      refresh: Evaluator.evaluate(query.refresh, ctx),
      fetched?: previous.fetched?,
      data: previous.data,
      error: previous.error,
      loading?: true,
      refetching?: previous.fetched?
    }

    runtime = render(%{runtime | queries: Map.put(runtime.queries, query.id, entry)})
    {runtime, [{:run_query, query.id, tool, args}]}
  end

  defp request(%{tool: tool, args: args}, ctx) do
    tool = tool |> Evaluator.evaluate(ctx) |> tool_name()

    args =
      case Evaluator.evaluate(args, ctx) do
        map when is_map(map) and not is_struct(map) -> map
        _other -> %{}
      end

    {tool, args}
  end

  defp tool_name(nil), do: ""
  defp tool_name(name), do: Value.stringify(name)

  defp settle_query(entry, _query_id, {:ok, data}),
    do: %{
      entry
      | data: HostValue.normalize(data),
        fetched?: true,
        error: nil,
        loading?: false,
        refetching?: false
    }

  defp settle_query(entry, query_id, {:error, reason}),
    do: %{
      entry
      | error: tool_error(:query, query_id, entry.tool, reason),
        loading?: false,
        refetching?: false
    }

  defp refresh_effects(query_id, %{refresh: seconds}) when is_number(seconds) and seconds > 0,
    do: [{:schedule_refresh, query_id, seconds}]

  defp refresh_effects(_query_id, _entry), do: []

  # While loading, a second run is rejected and the rest of its plan stops.
  defp start_mutation(runtime, id, rest, form) do
    mutation = Enum.find(runtime.program.mutations, &(&1.id == id))

    case {mutation, Map.get(runtime.mutations, id)} do
      {nil, _state} ->
        {runtime, []}

      {_mutation, %{result: %{"status" => "loading"}}} ->
        {runtime, []}

      {mutation, _state} ->
        {tool, args} = request(mutation, context(runtime))
        run_ref = make_ref()

        loading = %{
          result: %{"status" => "loading", "data" => nil, "error" => nil},
          error: nil,
          tool: tool
        }

        runtime = %{
          runtime
          | mutations: Map.put(runtime.mutations, id, loading),
            runs: Map.put(runtime.runs, run_ref, %{id: id, steps: rest, form: form})
        }

        {render(runtime), [{:run_mutation, run_ref, tool, args}]}
    end
  end

  defp settle_mutation(runtime, run, {:ok, data}) do
    tool = runtime.mutations[run.id].tool

    success = %{
      result: %{"status" => "success", "data" => HostValue.normalize(data), "error" => nil},
      error: nil,
      tool: tool
    }

    runtime = render(%{runtime | mutations: Map.put(runtime.mutations, run.id, success)})
    run_steps(runtime, run.steps, run.form, [])
  end

  defp settle_mutation(runtime, run, {:error, reason}) do
    tool = runtime.mutations[run.id].tool
    error = tool_error(:mutation, run.id, tool, reason)

    failed = %{
      result: %{"status" => "error", "data" => nil, "error" => error.message},
      error: error,
      tool: tool
    }

    {render(%{runtime | mutations: Map.put(runtime.mutations, run.id, failed)}), []}
  end

  defp tool_error(source, statement_id, tool, {:tool_not_found, available}) do
    %Error{
      source: source,
      code: "tool-not-found",
      statement_id: statement_id,
      tool_name: tool,
      message: ~s(Tool "#{tool}" was not found),
      hint: available_tools(available)
    }
  end

  defp tool_error(source, statement_id, tool, reason) do
    %Error{
      source: source,
      code: "tool-error",
      statement_id: statement_id,
      tool_name: tool,
      message:
        ~s(Tool "#{tool}" failed: #{if is_binary(reason), do: reason, else: inspect(reason)})
    }
  end

  defp available_tools([]), do: "No tools are available"
  defp available_tools(names), do: "Available tools: " <> Enum.join(names, ", ")

  defp current_errors(runtime) do
    query_errors = for {_id, %{error: %Error{} = error}} <- runtime.queries, do: error
    mutation_errors = for {_id, %{error: %Error{} = error}} <- runtime.mutations, do: error
    runtime.program.errors ++ runtime.render_errors ++ query_errors ++ mutation_errors
  end
end
