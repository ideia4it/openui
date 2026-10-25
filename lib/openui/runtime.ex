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
    * `{:schedule_refresh, query_id, seconds}`: call `refresh/2` later.

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

  alias OpenUI.{ActionPlan, Binding, Element, Event, Library, Program}
  alias OpenUI.Runtime.{Context, Evaluator, Validation}

  defstruct [
    :library,
    program: %Program{},
    store: %{},
    pristine: MapSet.new(),
    fields: %{},
    forms: %{},
    finished?: false,
    tree: nil,
    elements: %{},
    render_errors: [],
    field_errors: %{}
  ]

  @type effect ::
          {:emit, Event.t()}
          | {:run_query, String.t(), String.t(), map()}
          | {:run_mutation, reference(), String.t(), map()}
          | {:schedule_refresh, String.t(), number()}

  @type t :: %__MODULE__{}

  @doc """
  Starts a runtime. Options: `:fields`, `:forms` and `:state`, the state a
  host persisted earlier, applied over the program's defaults.
  """
  @spec new(Library.t() | module(), keyword()) :: t()
  def new(library, opts \\ []) do
    %__MODULE__{
      library: Library.resolve(library),
      fields: Map.new(Keyword.get(opts, :fields, %{})),
      forms: Map.new(Keyword.get(opts, :forms, %{})),
      store: Map.new(Keyword.get(opts, :state, %{}))
    }
    |> render()
  end

  @doc """
  Loads a program, from a stream frame or an edit. Declared defaults apply to
  state the person has not changed; no key is ever deleted. Nothing runs
  until `finish/1`.
  """
  @spec load(t(), Program.t()) :: {t(), [effect()]}
  def load(%__MODULE__{} = runtime, %Program{} = program) do
    runtime = %{runtime | program: program} |> apply_defaults() |> render()
    {runtime, []}
  end

  @doc "Marks the end of the stream."
  @spec finish(t()) :: {t(), [effect()]}
  def finish(%__MODULE__{} = runtime), do: {%{runtime | finished?: true}, []}

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
      {:ok, element} -> {write_field(runtime, key, element, value), []}
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
      state: Map.new(runtime.store, fn {name, value} -> {name, unwrap(value)} end)
    }
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

  defp field_value(runtime, key, element) do
    case bound_state(element) do
      %Binding{name: name} ->
        runtime.store |> Map.get(name) |> unwrap()

      nil ->
        name = element.props[Keyword.fetch!(runtime.fields[element.type], :name)]

        fields =
          if form = form_name(runtime, key), do: form_fields(runtime, form), else: runtime.store

        fields |> Map.get(name) |> unwrap()
    end
  end

  defp run_steps(runtime, [], _form, effects), do: {runtime, Enum.reverse(effects)}

  defp run_steps(runtime, [step | rest], form, effects) do
    {runtime, step_effects} = run_step(runtime, step, form)
    run_steps(runtime, rest, form, Enum.reverse(step_effects, effects))
  end

  defp run_step(runtime, {:set, name, value}, _form) do
    value = Evaluator.evaluate(value, context(runtime))
    {runtime |> set_state(name, value) |> render(), []}
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

    {render(runtime), []}
  end

  defp run_step(runtime, {:to_assistant, message, context}, form) do
    params = if context == nil, do: %{}, else: %{"context" => context}
    {runtime, [{:emit, event(runtime, "continue_conversation", message, params, form)}]}
  end

  defp run_step(runtime, {:open_url, url}, form),
    do: {runtime, [{:emit, event(runtime, "open_url", "", %{"url" => url}, form)}]}

  defp run_step(runtime, {:custom, name, params}, form),
    do: {runtime, [{:emit, event(runtime, name, "", params, form)}]}

  defp run_step(runtime, {:run, _id, _kind}, _form), do: {runtime, []}

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
end
