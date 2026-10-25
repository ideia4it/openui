defmodule OpenUI.Parser.Materializer do
  @moduledoc false
  # Lowers statements against a library, in one pass: references are inlined
  # (each place gets its own copy), component calls become `OpenUI.Element`s
  # with arguments mapped to props and checked, literals become plain values,
  # and expressions that need runtime data stay as AST for the evaluator.
  #
  # The struct is the pass's state: the errors, unresolved names and
  # still-unreached statements it collects, and the statement being lowered.

  alias OpenUI.{Builtins, Element, Library, Unknown}
  alias OpenUI.Parser.Validator

  defstruct [
    :library,
    :statement_id,
    symbols: %{},
    errors: [],
    unresolved: [],
    unreached: MapSet.new(),
    visited: MapSet.new(),
    partial?: false
  ]

  @reserved_calls ["Query", "Mutation"]

  @doc false
  def new(library, symbols, unreached, statement_id, partial?) do
    %__MODULE__{
      library: library,
      symbols: symbols,
      unreached: unreached,
      statement_id: statement_id,
      partial?: partial?
    }
  end

  @doc false
  def in_statement(%__MODULE__{} = ctx, statement_id, fun) do
    outer = ctx.statement_id
    {result, ctx} = fun.(%{ctx | statement_id: statement_id})
    {result, %{ctx | statement_id: outer}}
  end

  @doc "Lowers an expression in a value position: the result is a plain value, an element or AST."
  def value({:ref, name}, ctx), do: resolve_ref(name, ctx, :value)
  def value({:string, string}, ctx), do: {string, ctx}
  def value({:number, number}, ctx), do: {number, ctx}
  def value({:boolean, boolean}, ctx), do: {boolean, ctx}
  def value(:null, ctx), do: {nil, ctx}
  def value({:unresolved, _name}, ctx), do: {nil, ctx}
  def value({:array, items}, ctx), do: array_value(items, ctx)

  def value({:object, entries}, ctx) do
    {pairs, ctx} =
      Enum.map_reduce(entries, ctx, fn {key, entry}, ctx ->
        {entry, ctx} = value(entry, ctx)
        {{key, drop_unknown(entry)}, ctx}
      end)

    {Map.new(pairs), ctx}
  end

  def value({:call, name, _args}, ctx) when name in @reserved_calls,
    do: {nil, Validator.issue(ctx, name, "", "inline-reserved")}

  def value({:call, name, args}, ctx) do
    if runtime_call?(name, ctx.library),
      do: call(name, args, ctx, %{}),
      else: {nil, Validator.issue(ctx, name, "", "unknown-function")}
  end

  def value({:component, name, _args}, ctx) when name in @reserved_calls,
    do: {nil, Validator.issue(ctx, name, "", "inline-reserved")}

  def value({:component, name, args}, ctx) do
    case Library.component(ctx.library, name) do
      nil -> {%Unknown{type: name}, Validator.issue(ctx, name, "", "unknown-component")}
      component -> element(component, args, ctx)
    end
  end

  def value(ast, ctx), do: expression(ast, ctx)

  @doc "Lowers an expression the evaluator will run: references are inlined, calls checked."
  # The iterator names in scope are a plain map, not a MapSet: OTP 28 dialyzer
  # loses MapSet opacity through this recursion.
  def expression(ast, ctx), do: expression(ast, ctx, %{})

  defp expression({:ref, name} = ast, ctx, scoped) do
    if Map.has_key?(scoped, name), do: {ast, ctx}, else: resolve_ref(name, ctx, :expr)
  end

  defp expression({:call, name, args}, ctx, scoped) do
    if runtime_call?(name, ctx.library),
      do: call(name, args, ctx, scoped),
      else: {:null, Validator.issue(ctx, name, "", "unknown-function")}
  end

  # A component in a computed expression stays in the tree, even an unknown
  # one, so its error has something to point at; it renders nothing.
  defp expression({:component, name, args}, ctx, scoped) do
    {args, ctx} = expressions(args, ctx, scoped)

    ctx =
      if name in @reserved_calls or Library.component(ctx.library, name),
        do: ctx,
        else: Validator.issue(ctx, name, "", "unknown-component")

    {{:component, name, args}, ctx}
  end

  defp expression({:array, items}, ctx, scoped) do
    {items, ctx} = expressions(items, ctx, scoped)
    {{:array, items}, ctx}
  end

  defp expression({:object, entries}, ctx, scoped) do
    {entries, ctx} =
      Enum.map_reduce(entries, ctx, fn {key, entry}, ctx ->
        {entry, ctx} = expression(entry, ctx, scoped)
        {{key, entry}, ctx}
      end)

    {{:object, entries}, ctx}
  end

  defp expression({:binary, op, left, right}, ctx, scoped) do
    {left, ctx} = expression(left, ctx, scoped)
    {right, ctx} = expression(right, ctx, scoped)
    {{:binary, op, left, right}, ctx}
  end

  defp expression({:unary, op, operand}, ctx, scoped) do
    {operand, ctx} = expression(operand, ctx, scoped)
    {{:unary, op, operand}, ctx}
  end

  defp expression({:ternary, condition, then_branch, else_branch}, ctx, scoped) do
    {[condition, then_branch, else_branch], ctx} =
      expressions([condition, then_branch, else_branch], ctx, scoped)

    {{:ternary, condition, then_branch, else_branch}, ctx}
  end

  defp expression({:member, object, field}, ctx, scoped) do
    {object, ctx} = expression(object, ctx, scoped)
    {{:member, object, field}, ctx}
  end

  defp expression({:index, object, index}, ctx, scoped) do
    {[object, index], ctx} = expressions([object, index], ctx, scoped)
    {{:index, object, index}, ctx}
  end

  defp expression({:assign, name, assigned}, ctx, scoped) do
    {assigned, ctx} = expression(assigned, ctx, scoped)
    {{:assign, name, assigned}, ctx}
  end

  defp expression(ast, ctx, _scoped), do: {ast, ctx}

  defp expressions(asts, ctx, scoped), do: Enum.map_reduce(asts, ctx, &expression(&1, &2, scoped))

  # Inside an array, a dropped component or an unresolved reference leaves no
  # hole; an explicit null stays. An unknown component keeps its place as a
  # marker for the renderer's diagnostic.
  defp array_value(items, ctx) do
    {kept, ctx} =
      Enum.reduce(items, {[], ctx}, fn
        {:unresolved, _name}, acc ->
          acc

        item, {kept, ctx} ->
          case value(item, ctx) do
            {nil, ctx} when elem(item, 0) in [:component, :call, :ref] -> {kept, ctx}
            {value, ctx} -> {[value | kept], ctx}
          end
      end)

    {Enum.reverse(kept), ctx}
  end

  defp element(component, args, ctx) do
    params = component.props
    owner = component.name

    {props, drop?, ctx} =
      params
      |> Enum.zip(args)
      |> Enum.reduce({%{}, false, ctx}, fn {param, arg}, {props, drop?, ctx} ->
        {value, ctx} = value(arg, ctx)
        prop(props, param, drop_unknown(value), owner, drop?, ctx)
      end)

    ctx =
      if length(args) > length(params),
        do:
          Validator.issue(ctx, owner, "", "excess-args",
            declared: length(params),
            got: length(args)
          ),
        else: ctx

    case fill_missing_required(props, params, owner, ctx) do
      {:ok, props, ctx} when not drop? -> {%Element{type: owner, props: props}, ctx}
      {_result, _props, ctx} -> {nil, ctx}
    end
  end

  defp prop(props, param, value, owner, drop?, ctx) do
    case Validator.check(value, param.schema, owner, "/" <> param.name, ctx) do
      {{:keep, value}, ctx} ->
        {Map.put(props, param.name, value), drop?, ctx}

      {:invalid, ctx} ->
        case Validator.resolve_invalid(param.required?, param.default) do
          :invalid -> {Map.put(props, param.name, value), true, ctx}
          :remove -> {props, drop?, ctx}
          {:keep, default} -> {Map.put(props, param.name, default), drop?, ctx}
        end
    end
  end

  # A required prop that is absent or null takes its default; without one the
  # component is dropped and every such prop is reported.
  defp fill_missing_required(props, params, owner, ctx) do
    Enum.reduce(params, {:ok, props, ctx}, fn param, {status, props, ctx} ->
      cond do
        not param.required? or Map.get(props, param.name) != nil ->
          {status, props, ctx}

        param.default != :none ->
          {status, Map.put(props, param.name, param.default), ctx}

        true ->
          {:dropped, props,
           Validator.absent_issue(ctx, props, param.name, owner, "/" <> param.name)}
      end
    end)
  end

  defp call("Each", [array, iterator, template | rest], ctx, scoped) do
    case iterator_name(iterator) do
      nil ->
        call_args("Each", [array, iterator, template | rest], ctx, scoped)

      name ->
        inner = Map.put(scoped, name, true)
        {[array, template | rest], ctx} = expressions([array, template | rest], ctx, inner)
        {{:call, "Each", [array, iterator, template | rest]}, ctx}
    end
  end

  defp call(name, args, ctx, scoped), do: call_args(name, args, ctx, scoped)

  defp call_args(name, args, ctx, scoped) do
    {args, ctx} = expressions(args, ctx, scoped)

    cond do
      name in @reserved_calls or name in Builtins.names() ->
        {{:call, name, args}, ctx}

      function = Library.function(ctx.library, name) ->
        checked_call(name, args, function.params, ctx, :function)

      action = Library.action(ctx.library, name) ->
        checked_call(name, args, action.params, ctx, :action)
    end
  end

  defp iterator_name({:ref, name}), do: name
  defp iterator_name({:string, name}), do: name
  defp iterator_name(_other), do: nil

  # Literal arguments of a library function or action are checked when
  # parsing, like props. An invalid call becomes null for a function and an
  # empty plan (a no-op) for an action. An action also does
  # nothing when any argument was reported, even one that has a default, so
  # it never runs with a value the model did not write.
  defp checked_call(name, args, params, ctx, kind) do
    errors_before = length(ctx.errors)

    ctx =
      if length(args) > length(params),
        do:
          Validator.issue(ctx, name, "", "excess-args",
            declared: length(params),
            got: length(args)
          ),
        else: ctx

    {checked, invalid?, ctx} =
      params
      |> Enum.with_index()
      |> Enum.reduce({[], false, ctx}, fn {param, index}, {checked, invalid?, ctx} ->
        {arg, invalid_arg?, ctx} =
          check_arg(name, param, Enum.at(args, index), index < length(args), ctx)

        {[arg | checked], invalid? or invalid_arg?, ctx}
      end)

    action_reported? = kind == :action and length(ctx.errors) > errors_before

    if invalid? or action_reported? do
      {invalid_call(kind), ctx}
    else
      {{:call, name, checked |> Enum.reverse() |> Enum.take(length(args))}, ctx}
    end
  end

  defp invalid_call(:function), do: :null
  defp invalid_call(:action), do: {:call, "Action", [{:array, []}]}

  defp check_arg(owner, param, arg, given?, ctx) do
    case literal(arg) do
      :dynamic -> {arg, false, ctx}
      {:ok, nil} -> check_null_arg(owner, param, arg, given?, ctx)
      {:ok, literal} -> check_literal_arg(owner, param, arg, literal, ctx)
    end
  end

  defp check_null_arg(owner, param, arg, given?, ctx) do
    if param.required? and param.default == :none do
      code = if given?, do: "null-required", else: "missing-required"
      {arg, true, Validator.issue(ctx, owner, "/" <> param.name, code)}
    else
      {arg || :null, false, ctx}
    end
  end

  defp check_literal_arg(owner, param, arg, literal, ctx) do
    case Validator.check(literal, param.schema, owner, "/" <> param.name, ctx) do
      {{:keep, ^literal}, ctx} -> {arg, false, ctx}
      {{:keep, cleaned}, ctx} -> {to_ast(cleaned), false, ctx}
      {:invalid, ctx} -> resolved_arg(param, ctx)
    end
  end

  defp resolved_arg(param, ctx) do
    case Validator.resolve_invalid(param.required?, param.default) do
      :invalid -> {:null, true, ctx}
      :remove -> {:null, false, ctx}
      {:keep, default} -> {to_ast(default), false, ctx}
    end
  end

  defp literal(nil), do: {:ok, nil}
  defp literal(:null), do: {:ok, nil}
  defp literal({:string, string}), do: {:ok, string}
  defp literal({:number, number}), do: {:ok, number}
  defp literal({:boolean, boolean}), do: {:ok, boolean}

  defp literal({:array, items}) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case literal(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        :dynamic -> {:halt, :dynamic}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :dynamic -> :dynamic
    end)
  end

  defp literal({:object, entries}) do
    case literal({:array, Enum.map(entries, &elem(&1, 1))}) do
      {:ok, values} -> {:ok, entries |> Enum.map(&elem(&1, 0)) |> Enum.zip(values) |> Map.new()}
      :dynamic -> :dynamic
    end
  end

  defp literal(_ast), do: :dynamic

  defp to_ast(nil), do: :null
  defp to_ast(value) when is_binary(value), do: {:string, value}
  defp to_ast(value) when is_number(value), do: {:number, value}
  defp to_ast(value) when is_boolean(value), do: {:boolean, value}
  defp to_ast(value) when is_list(value), do: {:array, Enum.map(value, &to_ast/1)}

  defp to_ast(value) when is_map(value),
    do: {:object, Enum.map(value, fn {key, item} -> {key, to_ast(item)} end)}

  defp resolve_ref(name, ctx, mode) do
    if MapSet.member?(ctx.visited, name) or not Map.has_key?(ctx.symbols, name) do
      {if(mode == :expr, do: {:unresolved, name}, else: nil),
       %{ctx | unresolved: [name | ctx.unresolved]}}
    else
      ctx = %{ctx | unreached: MapSet.delete(ctx.unreached, name)}
      resolve_symbol(name, Map.fetch!(ctx.symbols, name), ctx, mode)
    end
  end

  defp resolve_symbol(name, {:component, "Query", _args}, ctx, _mode),
    do: {{:runtime_ref, name, :query}, ctx}

  defp resolve_symbol(name, {:component, "Mutation", _args}, ctx, _mode),
    do: {{:runtime_ref, name, :mutation}, ctx}

  defp resolve_symbol(name, target, ctx, mode) do
    {result, ctx} =
      in_statement(%{ctx | visited: MapSet.put(ctx.visited, name)}, name, fn ctx ->
        if mode == :value, do: value(target, ctx), else: expression(target, ctx)
      end)

    {tag(result, name, mode), %{ctx | visited: MapSet.delete(ctx.visited, name)}}
  end

  defp tag(%Element{} = element, name, :value), do: %{element | statement_id: name}
  defp tag(%Unknown{} = unknown, name, :value), do: %{unknown | statement_id: name}
  defp tag(result, _name, _mode), do: result

  defp drop_unknown(%Unknown{}), do: nil
  defp drop_unknown(value), do: value

  defp runtime_call?(name, library) do
    name in @reserved_calls or name in Builtins.names() or Library.function(library, name) != nil or
      Library.action(library, name) != nil
  end
end
