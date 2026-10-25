defmodule OpenUI.Canonical do
  @moduledoc """
  The canonical form of a program at stream end, as the OpenUI conformance
  fixtures summarize it (`spec/fixtures/1.0/README.md`, "How the tree is
  summarized").

  It holds only spec concepts (component types and props, resolved values,
  error codes, unresolved names, orphans, state), which makes it a stable
  thing to compare across implementations and in tests.
  """

  alias OpenUI.{ActionPlan, Binding, Element, Error, Library, Program, Unknown}
  alias OpenUI.Runtime.{Context, Evaluator}

  @idle_mutation %{"status" => "idle", "data" => nil, "error" => nil}

  @doc """
  Evaluates the program as at stream end, before any query returns: state at
  its defaults, each query at its defaults and each mutation idle.
  """
  @spec result(Program.t(), Library.t() | module()) :: map()
  def result(%Program{} = program, library) do
    library = Library.resolve(library)
    ctx = stream_end_context(program, library)
    {tree, runtime_errors} = Evaluator.evaluate_root(program, ctx)
    errors = program.errors ++ runtime_errors

    %{
      "root" => summarize(tree, library, &Evaluator.evaluate(&1, ctx)),
      "errors" => Enum.map(errors, &error_entry/1),
      "errorObjects" => Enum.map(errors, &Error.to_map/1),
      "unresolved" => program.unresolved,
      "orphans" => program.orphans,
      "incomplete" => program.incomplete,
      "state" => ctx.state
    }
  end

  @doc "The evaluated tree at stream end, as `result/2` summarizes it."
  @spec tree(Program.t(), Library.t() | module()) :: Element.t() | nil
  def tree(%Program{} = program, library) do
    library = Library.resolve(library)
    {tree, _errors} = Evaluator.evaluate_root(program, stream_end_context(program, library))
    tree
  end

  defp stream_end_context(program, library) do
    defaults_ctx = %Context{library: library}

    %Context{
      library: library,
      state:
        Map.new(program.state, fn {name, default} ->
          {name, Evaluator.evaluate(default, defaults_ctx)}
        end),
      queries: Map.new(program.queries, &{&1.id, Evaluator.evaluate(&1.defaults, defaults_ctx)}),
      mutations: Map.new(program.mutations, &{&1.id, @idle_mutation})
    }
  end

  @doc """
  Summarizes an evaluated value: a component becomes `%{"type", "props"}`
  without its null props, an action plan `%{"actions" => [...]}`, a binding
  `%{"$binding" => name}`. `evaluate` reads the value of each `@Set`.
  """
  @spec summarize(term(), Library.t(), (term() -> term())) :: term()
  def summarize(%Element{} = element, library, evaluate) do
    props =
      element.props
      |> Enum.map(fn {name, value} -> {name, summarize(value, library, evaluate)} end)
      |> Enum.reject(fn {_name, summary} -> is_nil(summary) end)
      |> Map.new()

    %{"type" => element.type, "props" => props}
  end

  def summarize(%ActionPlan{steps: steps}, library, evaluate),
    do: %{"actions" => Enum.map(steps, &step(&1, library, evaluate))}

  def summarize(%Binding{name: name}, _library, _evaluate), do: %{"$binding" => name}

  def summarize(list, library, evaluate) when is_list(list) do
    for item <- list, not match?(%Unknown{}, item), do: summarize(item, library, evaluate)
  end

  def summarize(map, library, evaluate) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {key, value} -> {key, summarize(value, library, evaluate)} end)

  def summarize(%Unknown{}, _library, _evaluate), do: nil
  def summarize(value, _library, _evaluate), do: value

  defp step({:to_assistant, message, nil}, _library, _evaluate),
    do: action("ToAssistant", [message])

  defp step({:to_assistant, message, context}, library, evaluate),
    do: action("ToAssistant", [message, summarize(context, library, evaluate)])

  defp step({:open_url, url}, _library, _evaluate), do: action("OpenUrl", [url])

  defp step({:set, target, value}, _library, evaluate),
    do: action("Set", [target, evaluate.(value)])

  defp step({:reset, targets}, _library, _evaluate), do: action("Reset", targets)
  defp step({:run, statement_id, _kind}, _library, _evaluate), do: action("Run", [statement_id])

  defp step({:custom, name, params}, library, evaluate) do
    declared = Library.action(library, name)
    action(name, Enum.map(declared.params, &summarize(params[&1.name], library, evaluate)))
  end

  defp action(name, args), do: %{"action" => name, "args" => args}

  defp error_entry(%Error{code: code, statement_id: nil}), do: %{"code" => code}

  defp error_entry(%Error{code: code, statement_id: id}),
    do: %{"code" => code, "statementId" => id}
end
