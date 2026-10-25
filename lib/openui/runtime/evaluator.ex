defmodule OpenUI.Runtime.Evaluator do
  @moduledoc """
  Evaluates a parsed program into a tree of plain values (language.md,
  sections 3 and 6.3).

  Evaluation never raises on generated content. A library function that
  raises, or gets or returns a value of the wrong type, evaluates to `nil`
  and reports a `runtime-error` naming the prop it was evaluated for.
  """

  alias OpenUI.{ActionPlan, Binding, Builtins, Element, Error, Library, Program, Unknown}
  alias OpenUI.Parser.{Materializer, Validator}
  alias OpenUI.Runtime.Context
  alias OpenUI.Runtime.HostValue
  alias OpenUI.Runtime.Value

  @idle_mutation %{"status" => "idle", "data" => nil, "error" => nil}
  @reserved_calls ["Query", "Mutation"]

  @doc """
  Evaluates the program's entry. Returns the evaluated tree, with a `key` on
  every element, or `nil` when nothing renders, and the runtime errors.
  """
  @spec evaluate_root(Program.t(), Context.t()) :: {Element.t() | nil, [Error.t()]}
  def evaluate_root(%Program{root: %Element{} = root}, %Context{} = ctx) do
    {tree, errors} = element(root, env(ctx), [])
    {assign_keys(tree, "0"), Enum.reverse(errors)}
  end

  def evaluate_root(%Program{root_expression: nil}, %Context{}), do: {nil, []}

  def evaluate_root(%Program{root_expression: expression}, %Context{} = ctx) do
    case interpret(expression, env(ctx), []) do
      {%Element{} = tree, errors} ->
        {assign_keys(tree, "0"), Enum.reverse(errors)}

      {_other, errors} ->
        no_root = %Error{
          source: :runtime,
          code: "no-root",
          statement_id: "root",
          message: "root does not evaluate to a component"
        }

        {nil, Enum.reverse([no_root | errors])}
    end
  end

  @doc "Evaluates one expression."
  @spec evaluate(OpenUI.Parser.Expression.ast() | term(), Context.t()) :: term()
  def evaluate(ast, %Context{} = ctx) do
    {value, _errors} = interpret(ast, env(ctx), [])
    value
  end

  defp env(ctx), do: %{ctx: ctx, scope: %{}, owner: nil}

  defp element(%Element{} = element, env, errors) do
    component = Library.component(env.ctx.library, element.type)

    {props, errors} =
      Enum.reduce(element.props, {%{}, errors}, fn {name, value}, {props, errors} ->
        owner_env = %{env | owner: {element.type, element.statement_id, name}}
        {value, errors} = prop_value(value, bindable?(component, name), owner_env, errors)
        {Map.put(props, name, value), errors}
      end)

    {%{element | props: props}, errors}
  end

  defp bindable?(nil, _name), do: false

  defp bindable?(component, name),
    do: Enum.any?(component.props, &(&1.name == name and &1.bindable?))

  defp prop_value({:state, name}, true, _env, errors), do: {%Binding{name: name}, errors}
  defp prop_value({:assign, name, _value}, true, _env, errors), do: {%Binding{name: name}, errors}
  defp prop_value(%Element{} = value, _bindable?, env, errors), do: element(value, env, errors)
  defp prop_value(%Unknown{} = value, _bindable?, _env, errors), do: {value, errors}

  defp prop_value(ast, _bindable?, env, errors) when is_tuple(ast) or ast == :null,
    do: interpret(ast, env, errors)

  defp prop_value(list, _bindable?, env, errors) when is_list(list),
    do: Enum.map_reduce(list, errors, &prop_value(&1, false, env, &2))

  defp prop_value(map, _bindable?, env, errors) when is_map(map) and not is_struct(map) do
    {pairs, errors} =
      Enum.map_reduce(map, errors, fn {key, value}, errors ->
        {value, errors} = prop_value(value, false, env, errors)
        {{key, value}, errors}
      end)

    {Map.new(pairs), errors}
  end

  defp prop_value(value, _bindable?, _env, errors), do: {value, errors}

  defp interpret({:string, string}, _env, errors), do: {string, errors}
  defp interpret({:number, number}, _env, errors), do: {number, errors}
  defp interpret({:boolean, boolean}, _env, errors), do: {boolean, errors}
  defp interpret(:null, _env, errors), do: {nil, errors}
  defp interpret({:unresolved, _name}, _env, errors), do: {nil, errors}
  defp interpret({:literal, value}, _env, errors), do: {value, errors}
  defp interpret({:state, name}, env, errors), do: {Map.get(env.ctx.state, name), errors}
  defp interpret({:assign, name, _value}, env, errors), do: {Map.get(env.ctx.state, name), errors}
  defp interpret({:ref, name}, env, errors), do: {Map.get(env.scope, name), errors}

  defp interpret({:runtime_ref, id, :query}, env, errors),
    do: {Map.get(env.ctx.queries, id), errors}

  defp interpret({:runtime_ref, id, :mutation}, env, errors),
    do: {Map.get(env.ctx.mutations, id, @idle_mutation), errors}

  defp interpret({:array, items}, env, errors) do
    items
    |> Enum.reject(&left_out_of_array?(&1, env))
    |> Enum.map_reduce(errors, &interpret(&1, env, &2))
  end

  defp interpret({:object, entries}, env, errors) do
    {pairs, errors} =
      Enum.map_reduce(entries, errors, fn {key, value}, errors ->
        {value, errors} = interpret(value, env, errors)
        {{key, value}, errors}
      end)

    {Map.new(pairs), errors}
  end

  defp interpret({:component, name, _args}, _env, errors) when name in @reserved_calls,
    do: {nil, errors}

  defp interpret({:component, name, args}, env, errors) do
    case Library.component(env.ctx.library, name) do
      nil -> {nil, errors}
      component -> component_value(component, args, env, errors)
    end
  end

  defp interpret({:call, name, args}, env, errors), do: call(name, args, env, errors)

  defp interpret({:binary, "&&", left, right}, env, errors) do
    {left, errors} = interpret(left, env, errors)
    if Value.truthy?(left), do: interpret(right, env, errors), else: {left, errors}
  end

  defp interpret({:binary, "||", left, right}, env, errors) do
    {left, errors} = interpret(left, env, errors)
    if Value.truthy?(left), do: {left, errors}, else: interpret(right, env, errors)
  end

  defp interpret({:binary, op, left, right}, env, errors) do
    {left, errors} = interpret(left, env, errors)
    {right, errors} = interpret(right, env, errors)
    {Value.binary_op(op, left, right), errors}
  end

  defp interpret({:unary, op, operand}, env, errors) do
    {operand, errors} = interpret(operand, env, errors)
    {Value.unary_op(op, operand), errors}
  end

  defp interpret({:ternary, condition, then_branch, else_branch}, env, errors) do
    {condition, errors} = interpret(condition, env, errors)
    interpret(if(Value.truthy?(condition), do: then_branch, else: else_branch), env, errors)
  end

  defp interpret({:member, object, field}, env, errors) do
    {object, errors} = interpret(object, env, errors)
    {member(object, field), errors}
  end

  defp interpret({:index, object, index}, env, errors) do
    {object, errors} = interpret(object, env, errors)
    {index, errors} = interpret(index, env, errors)
    {index(object, index), errors}
  end

  defp interpret(%Element{} = value, env, errors), do: element(value, env, errors)
  defp interpret(value, _env, errors), do: {value, errors}

  # Inside an array, an unresolved reference and an unknown component leave no
  # hole, in computed expressions too (language.md, section 8.4).
  defp left_out_of_array?({:unresolved, _name}, _env), do: true

  defp left_out_of_array?({:component, name, _args}, env),
    do: name not in @reserved_calls and Library.component(env.ctx.library, name) == nil

  defp left_out_of_array?(_ast, _env), do: false

  defp component_value(component, args, env, errors) do
    {props, errors} =
      component.props
      |> Enum.zip(args)
      |> Enum.reduce({%{}, errors}, fn {param, arg}, {props, errors} ->
        {value, errors} = prop_value(arg, param.bindable?, env, errors)
        {Map.put(props, param.name, value), errors}
      end)

    {%Element{type: component.name, props: props}, errors}
  end

  defp member(nil, _field), do: nil
  defp member(list, "length") when is_list(list), do: length(list)
  defp member(list, field) when is_list(list), do: Enum.map(list, &member_of_item(&1, field))
  defp member(map, field) when is_map(map) and not is_struct(map), do: Map.get(map, field)

  defp member(string, "length") when is_binary(string), do: Value.text_length(string)

  defp member(_other, _field), do: nil

  defp member_of_item(item, field) when is_map(item) and not is_struct(item),
    do: Map.get(item, field)

  # Arrays are objects in JavaScript: an inner array answers "length" and its
  # numeric keys, so m.0 plucks the first item of every row.
  defp member_of_item(list, "length") when is_list(list), do: length(list)

  defp member_of_item(list, field) when is_list(list) do
    case Integer.parse(field) do
      {position, ""} when position >= 0 -> Enum.at(list, position)
      _other -> nil
    end
  end

  defp member_of_item(_item, _field), do: nil

  defp index(nil, _index), do: nil
  defp index(_object, nil), do: nil

  defp index(list, index) when is_list(list) do
    case Value.to_number(index) do
      position when is_integer(position) and position >= 0 -> Enum.at(list, position)
      _other -> nil
    end
  end

  defp index(map, index) when is_map(map) and not is_struct(map),
    do: Map.get(map, Value.stringify(index))

  defp index(_object, _index), do: nil

  defp call("Each", args, env, errors), do: each(args, env, errors)
  defp call(name, _args, _env, errors) when name in @reserved_calls, do: {nil, errors}

  defp call("ToAssistant", args, env, errors) do
    {[message, context | _], errors} = interpret_args(args, 2, env, errors)
    {plan([{:to_assistant, text(message), context}]), errors}
  end

  defp call("OpenUrl", args, env, errors) do
    {[url | _], errors} = interpret_args(args, 1, env, errors)
    {plan([{:open_url, text(url)}]), errors}
  end

  defp call("Run", [{:runtime_ref, id, kind} | _], _env, errors),
    do: {plan([{:run, id, kind}]), errors}

  defp call("Run", _args, _env, errors), do: {plan([]), errors}

  defp call("Set", [{:state, name}, value | _], _env, errors),
    do: {plan([{:set, name, value}]), errors}

  defp call("Set", _args, _env, errors), do: {plan([]), errors}

  defp call("Reset", args, _env, errors),
    do: {plan(for({:state, name} <- args, do: name) |> reset_step()), errors}

  defp call("Action", [list | _], env, errors) do
    case interpret(list, env, errors) do
      {items, errors} when is_list(items) ->
        {plan(for(%ActionPlan{steps: steps} <- items, step <- steps, do: step)), errors}

      {_other, errors} ->
        {plan([]), errors}
    end
  end

  defp call("Action", [], _env, errors), do: {plan([]), errors}

  defp call(name, args, env, errors) do
    cond do
      Builtins.function?(name) ->
        {values, errors} = Enum.map_reduce(args, errors, &interpret(&1, env, &2))
        {OpenUI.Runtime.Builtins.call(name, values), errors}

      function = Library.function(env.ctx.library, name) ->
        call_function(function, args, env, errors)

      action = Library.action(env.ctx.library, name) ->
        custom_action(action, args, env, errors)

      true ->
        {nil, errors}
    end
  end

  defp plan(steps), do: %ActionPlan{steps: steps}

  defp reset_step([]), do: []
  defp reset_step(targets), do: [{:reset, targets}]

  defp interpret_args(args, count, env, errors) do
    args
    |> Enum.concat(List.duplicate(:null, count))
    |> Enum.take(count)
    |> Enum.map_reduce(errors, &interpret(&1, env, &2))
  end

  defp text(nil), do: ""
  defp text(value), do: Value.stringify(value)

  # The template is evaluated once per element, with the element put in place
  # of the loop variable first, so an action in the template keeps its own
  # element when it runs later.
  defp each([array, iterator, template | _rest], env, errors) do
    {items, errors} = interpret(array, env, errors)

    case iterator_name(iterator) do
      name when is_binary(name) and is_list(items) ->
        Enum.map_reduce(items, errors, fn item, errors ->
          template
          |> substitute(name, item)
          |> interpret(%{env | scope: Map.put(env.scope, name, item)}, errors)
        end)

      _other ->
        {[], errors}
    end
  end

  defp each(_args, _env, errors), do: {[], errors}

  defp iterator_name({:ref, name}), do: name
  defp iterator_name({:string, name}), do: name
  defp iterator_name(_other), do: nil

  defp substitute({:ref, name}, name, item), do: {:literal, item}

  # A nested @Each with the same loop variable shadows this one.
  defp substitute({:call, "Each", [array, iterator, template | rest]}, name, item) do
    if iterator_name(iterator) == name,
      do: {:call, "Each", [substitute(array, name, item), iterator, template | rest]},
      else:
        {:call, "Each",
         [substitute(array, name, item), iterator, substitute(template, name, item) | rest]}
  end

  defp substitute({:literal, _value} = literal, _name, _item), do: literal

  defp substitute(ast, name, item) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.map(&substitute(&1, name, item)) |> List.to_tuple()

  defp substitute(list, name, item) when is_list(list),
    do: Enum.map(list, &substitute(&1, name, item))

  defp substitute(other, _name, _item), do: other

  defp call_function(function, args, env, errors) do
    {values, errors} = call_values(function.params, args, env, errors)

    case check_call(function, values, env) do
      :missing -> {nil, errors}
      {:invalid, messages} -> {nil, report(errors, env, messages)}
      {:ok, values} -> run_function(function, values, env, errors)
    end
  end

  defp run_function(%{impl: nil} = function, _values, env, errors),
    do: {nil, report(errors, env, ["@#{function.name} has no implementation"])}

  defp run_function(function, values, env, errors) do
    result = function.impl.(values)

    case check_returns(function, HostValue.normalize(result), env) do
      {:ok, value} -> {value, errors}
      {:invalid, messages} -> {nil, report(errors, env, messages)}
    end
  rescue
    exception ->
      {nil, report(errors, env, ["@#{function.name} raised: " <> Exception.message(exception)])}
  catch
    kind, reason ->
      {nil, report(errors, env, ["@#{function.name} failed: #{inspect({kind, reason})}"])}
  end

  # A library action whose arguments do not check out does nothing, even when
  # a default could stand in, so it never runs with a value the model did not
  # write.
  defp custom_action(action, args, env, errors) do
    {values, errors} = call_values(action.params, args, env, errors)

    case check_call(action, values, env, strict: true) do
      :missing -> {plan([]), errors}
      {:invalid, messages} -> {plan([]), report(errors, env, messages)}
      {:ok, values} -> {plan([{:custom, action.name, values}]), errors}
    end
  end

  # Arguments map to params by position. An explicit null for an optional
  # param is left out, so its default applies.
  defp call_values(params, args, env, errors) do
    {values, errors} =
      params
      |> Enum.zip(args)
      |> Enum.map_reduce(errors, fn {param, arg}, errors ->
        {value, errors} = interpret(arg, env, errors)
        {{param, value}, errors}
      end)

    present =
      for {param, value} <- values, value != nil or param.required?, do: {param.name, value}

    {Map.new(present), errors}
  end

  # A required argument that is null when the call runs, with no default (an
  # unset $variable, an unresolved reference), makes the call null with no error.
  defp check_call(callable, values, env, opts \\ []) do
    if Enum.any?(callable.params, &missing_required?(&1, values)) do
      :missing
    else
      values = Enum.reduce(callable.params, values, &put_default/2)
      check_values(callable, values, env, Keyword.get(opts, :strict, false))
    end
  end

  defp missing_required?(param, values),
    do: param.required? and Map.get(values, param.name) == nil and param.default == :none

  defp put_default(%{default: :none}, values), do: values
  defp put_default(param, values), do: Map.put_new(values, param.name, param.default)

  defp check_values(callable, values, env, strict?) do
    ctx = Materializer.new(env.ctx.library, %{}, MapSet.new(), nil, false)

    {values, invalid?, ctx} =
      Enum.reduce(callable.params, {values, false, ctx}, fn param, acc ->
        check_param(callable.name, param, acc)
      end)

    messages = ctx.errors |> Enum.reverse() |> Enum.map(&"@#{callable.name}: #{&1.message}")

    if invalid? or (strict? and messages != []),
      do: {:invalid, messages},
      else: {:ok, values}
  end

  defp check_param(owner, param, {values, invalid?, ctx}) do
    if Map.has_key?(values, param.name) do
      case Validator.check(values[param.name], param.schema, owner, "/" <> param.name, ctx) do
        {{:keep, value}, ctx} -> {Map.put(values, param.name, value), invalid?, ctx}
        {:invalid, ctx} -> resolve_param(values, param, invalid?, ctx)
      end
    else
      {values, invalid?, ctx}
    end
  end

  defp resolve_param(values, param, invalid?, ctx) do
    case Validator.resolve_invalid(param.required?, param.default) do
      :invalid -> {values, true, ctx}
      :remove -> {Map.delete(values, param.name), invalid?, ctx}
      {:keep, default} -> {Map.put(values, param.name, default), invalid?, ctx}
    end
  end

  defp check_returns(%{returns: nil}, result, _env), do: {:ok, result}

  defp check_returns(function, result, env) do
    ctx = Materializer.new(env.ctx.library, %{}, MapSet.new(), nil, false)

    case Validator.check(result, function.returns, function.name, "/returns", ctx) do
      {{:keep, value}, _ctx} ->
        {:ok, value}

      {:invalid, ctx} ->
        {:invalid, Enum.map(Enum.reverse(ctx.errors), &"@#{function.name}: #{&1.message}")}
    end
  end

  defp report(errors, env, messages) do
    Enum.reduce(messages, errors, fn message, errors ->
      [runtime_error(env.owner, message) | errors]
    end)
  end

  defp runtime_error({type, statement_id, prop}, message) do
    %Error{
      source: :runtime,
      code: "runtime-error",
      component: type,
      statement_id: statement_id,
      message: ~s(Evaluating prop "#{prop}" on #{type} failed: #{message}),
      hint: ~s(Check the expression used for prop "#{prop}")
    }
  end

  defp runtime_error(nil, message),
    do: %Error{source: :runtime, code: "runtime-error", message: message}

  defp assign_keys(%Element{} = element, key) do
    props =
      Map.new(element.props, fn {name, value} -> {name, assign_key(value, "#{key}.#{name}")} end)

    %{element | key: key, props: props}
  end

  defp assign_key(%Element{} = element, key), do: assign_keys(element, key)
  defp assign_key(%Unknown{} = unknown, key), do: %{unknown | key: key}

  defp assign_key(list, key) when is_list(list),
    do:
      list
      |> Enum.with_index()
      |> Enum.map(fn {item, index} -> assign_key(item, "#{key}.#{index}") end)

  defp assign_key(map, key) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {field, value} -> {field, assign_key(value, "#{key}.#{field}")} end)

  defp assign_key(value, _key), do: value
end
