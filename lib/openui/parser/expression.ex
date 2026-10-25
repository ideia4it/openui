defmodule OpenUI.Parser.Expression do
  @moduledoc """
  Parses tokens into an expression tree (language.md, sections 1.5 and 1.6)
  by precedence climbing, and classifies statements (section 2.1).

  Like the lexer, parsing never fails: a token that cannot start an operand
  reads as `null`, a missing closer is assumed, and tokens left after a
  complete expression are dropped.
  """

  alias OpenUI.Parser.Lexer
  alias OpenUI.Runtime.Value
  alias OpenUI.Statement

  @type ast ::
          {:string, String.t()}
          | {:number, number()}
          | {:boolean, boolean()}
          | :null
          | {:array, [ast()]}
          | {:object, [{String.t(), ast()}]}
          | {:ref, String.t()}
          | {:state, String.t()}
          | {:component, String.t(), [ast()]}
          | {:call, String.t(), [ast()]}
          | {:binary, String.t(), ast(), ast()}
          | {:unary, String.t(), ast()}
          | {:ternary, ast(), ast(), ast()}
          | {:member, ast(), String.t()}
          | {:index, ast(), ast()}
          | {:assign, String.t(), ast()}
          | {:unresolved, String.t()}
          | {:runtime_ref, String.t(), :query | :mutation}

  # Built-in functions and steps need the @. Written bare before a paren they
  # read as a reference and lose their arguments; only Action works bare.
  @builtin_names ~w(Count First Last Sum Avg Min Max Sort Filter Round Abs Floor Ceil Each Run ToAssistant OpenUrl Set Reset)

  @precedence %{
    "?" => 1,
    "||" => 2,
    "&&" => 3,
    "==" => 4,
    "!=" => 4,
    ">" => 5,
    "<" => 5,
    ">=" => 5,
    "<=" => 5,
    "+" => 6,
    "-" => 6,
    "*" => 7,
    "/" => 7,
    "%" => 7,
    "." => 9,
    "[" => 9
  }
  @unary_precedence 8

  @doc "Parses one expression from `tokens`."
  @spec parse([Lexer.token()]) :: ast()
  def parse(tokens) when is_list(tokens) do
    {ast, _rest} = expression(Enum.reject(tokens, &(&1 == :newline)), 0)
    ast
  end

  @doc """
  Parses the source of one statement. Returns `nil` when the text does not
  have the `name = expression` shape.
  """
  @spec parse_statement(String.t()) :: Statement.t() | nil
  def parse_statement(source) when is_binary(source) do
    case Lexer.tokenize(source) do
      [{kind, id}, {:op, "="} | expression] when kind in [:ident, :state] ->
        ast = parse(expression)
        %Statement{id: id, kind: classify(id, ast), ast: ast, source: source}

      _other ->
        nil
    end
  end

  defp classify(_id, {:component, "Query", _args}), do: :query
  defp classify(_id, {:component, "Mutation", _args}), do: :mutation
  defp classify("$" <> _name, _ast), do: :state
  defp classify(_id, _ast), do: :value

  defp expression(tokens, min_precedence) do
    {left, rest} = prefix(tokens)
    infix_loop(left, rest, min_precedence)
  end

  defp infix_loop(left, [{:op, op} | _] = tokens, min_precedence) do
    if Map.get(@precedence, op, 0) > min_precedence do
      {left, rest} = infix(left, tokens)
      infix_loop(left, rest, min_precedence)
    else
      {left, tokens}
    end
  end

  defp infix_loop(left, tokens, _min_precedence), do: {left, tokens}

  defp prefix([{:string, value} | rest]), do: {{:string, value}, rest}
  defp prefix([{:string, value, :unterminated} | rest]), do: {{:string, value}, rest}
  defp prefix([{:number, value} | rest]), do: {{:number, value}, rest}
  defp prefix([{:literal, nil} | rest]), do: {:null, rest}
  defp prefix([{:literal, value} | rest]), do: {{:boolean, value}, rest}
  defp prefix([{:op, "["} | rest]), do: collection(rest, "]", &{:array, &1}, &array_item/1)
  defp prefix([{:op, "{"} | rest]), do: collection(rest, "}", &{:object, &1}, &object_entry/1)

  defp prefix([{:state, name}, {:op, "="} | rest]) do
    {value, rest} = expression(rest, 0)
    {{:assign, name, value}, rest}
  end

  defp prefix([{:state, name} | rest]), do: {{:state, name}, rest}

  defp prefix([{:ident, "Action"}, {:op, "("} | rest]), do: call(rest, &{:call, "Action", &1})

  defp prefix([{:ident, <<first, _::binary>> = name}, {:op, "("} | rest])
       when first in ?A..?Z and name not in @builtin_names,
       do: call(rest, &{:component, name, &1})

  defp prefix([{:ident, name} | rest]), do: {{:ref, name}, rest}
  defp prefix([{:at, name}, {:op, "("} | rest]), do: call(rest, &{:call, name, &1})
  defp prefix([{:at, name} | rest]), do: {{:ref, name}, rest}

  defp prefix([{:op, op} | rest]) when op in ["!", "-"] do
    {operand, rest} = expression(rest, @unary_precedence)
    {{:unary, op, operand}, rest}
  end

  defp prefix([{:op, "("} | rest]) do
    {inner, rest} = expression(rest, 0)
    {inner, eat(rest, ")")}
  end

  defp prefix([_unknown | rest]), do: {:null, rest}
  defp prefix([]), do: {:null, []}

  defp infix(left, [{:op, "?"} | rest]) do
    {then_branch, rest} = expression(rest, 0)
    {else_branch, rest} = expression(eat(rest, ":"), 0)
    {{:ternary, left, then_branch, else_branch}, rest}
  end

  defp infix(left, [{:op, "."} | rest]) do
    {field, rest} = key(rest)
    {{:member, left, field}, rest}
  end

  defp infix(left, [{:op, "["} | rest]) do
    {index, rest} = expression(rest, 0)
    {{:index, left, index}, eat(rest, "]")}
  end

  defp infix(left, [{:op, op} | rest]) do
    {right, rest} = expression(rest, Map.fetch!(@precedence, op))
    {{:binary, op, left, right}, rest}
  end

  defp call(tokens, build) do
    {args, rest} = items(tokens, ")", &array_item/1, [])
    {build.(args), rest}
  end

  defp collection(tokens, closer, build, read_item) do
    {items, rest} = items(tokens, closer, read_item, [])
    {build.(items), rest}
  end

  # Commas between items are optional and trailing commas are ignored.
  defp items([], _closer, _read_item, acc), do: {Enum.reverse(acc), []}
  defp items([{:op, closer} | rest], closer, _read_item, acc), do: {Enum.reverse(acc), rest}

  defp items(tokens, closer, read_item, acc) do
    {item, rest} = read_item.(tokens)
    items(eat(rest, ","), closer, read_item, [item | acc])
  end

  defp array_item(tokens), do: expression(tokens, 0)

  defp object_entry(tokens) do
    {name, rest} = key(tokens)
    {value, rest} = expression(eat(rest, ":"), 0)
    {{name, value}, rest}
  end

  # Object keys and member fields take names, strings, numbers and $ names (the
  # $ is dropped); any other token reads as the key "?".
  defp key([{:ident, name} | rest]), do: {name, rest}
  defp key([{:string, value} | rest]), do: {value, rest}
  defp key([{:string, value, :unterminated} | rest]), do: {value, rest}
  defp key([{:number, value} | rest]), do: {Value.stringify(value), rest}
  defp key([{:state, "$" <> name} | rest]), do: {name, rest}
  defp key([_other | rest]), do: {"?", rest}
  defp key([]), do: {"?", []}

  defp eat([{:op, op} | rest], op), do: rest
  defp eat(tokens, _op), do: tokens
end
