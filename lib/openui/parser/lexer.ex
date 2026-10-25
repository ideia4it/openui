defmodule OpenUI.Parser.Lexer do
  @moduledoc """
  Turns OpenUI Lang source into tokens (language.md, section 1.3).

  Lexing never fails: a character that matches no rule is skipped. Tokens:

    * `{:ident, name}`: an identifier, lowercase or uppercase (the parser
      decides whether it is a component);
    * `{:state, "$name"}` and `{:at, "Name"}` for `$name` and `@Name`;
    * `{:string, value}`, or `{:string, value, :unterminated}` when the text
      ends inside it;
    * `{:number, number}`, `{:literal, true | false | nil}`;
    * `{:op, text}` for every operator and punctuation mark;
    * `:newline`.

  A number with an exponent marker and no exponent digits (`1e`) is not a
  usable number in the spec; here it takes the value of its mantissa.
  """

  alias OpenUI.Runtime.Value

  @type token ::
          {:ident, String.t()}
          | {:state, String.t()}
          | {:at, String.t()}
          | {:string, String.t()}
          | {:string, String.t(), :unterminated}
          | {:number, number()}
          | {:literal, true | false | nil}
          | {:op, String.t()}
          | :newline

  @two_char_ops ["==", "!=", ">=", "<=", "&&", "||"]
  @one_char_ops ~w|( ) [ ] { } , : = ! > < . ? + * / % -|

  defguardp digit?(char) when char in ?0..?9
  defguardp letter?(char) when char in ?a..?z or char in ?A..?Z or char == ?_
  defguardp word_char?(char) when letter?(char) or digit?(char)

  @doc "Returns the tokens of `source`."
  @spec tokenize(String.t()) :: [token()]
  def tokenize(source) when is_binary(source), do: lex(source, [])

  defp lex(<<>>, tokens), do: Enum.reverse(tokens)
  defp lex(<<char, rest::binary>>, tokens) when char in [?\s, ?\t, ?\r], do: lex(rest, tokens)
  defp lex(<<?\n, rest::binary>>, tokens), do: lex(rest, [:newline | tokens])

  defp lex(<<?", _rest::binary>> = source, tokens) do
    {token, rest} = double_quoted(source)
    lex(rest, [token | tokens])
  end

  defp lex(<<?', rest::binary>>, tokens) do
    {token, rest} = single_quoted(rest, [])
    lex(rest, [token | tokens])
  end

  defp lex(<<?-, next, _rest::binary>> = source, tokens) when digit?(next) do
    if after_value?(tokens) do
      <<_minus, rest::binary>> = source
      lex(rest, [{:op, "-"} | tokens])
    else
      number(source, tokens)
    end
  end

  defp lex(<<char, _rest::binary>> = source, tokens) when digit?(char), do: number(source, tokens)

  defp lex(<<?$, next, _rest::binary>> = source, tokens) when letter?(next) do
    <<_dollar, rest::binary>> = source
    {name, rest} = take_word(rest)
    lex(rest, [{:state, "$" <> name} | tokens])
  end

  defp lex(<<?@, next, _rest::binary>> = source, tokens) when letter?(next) do
    <<_at, rest::binary>> = source
    {name, rest} = take_word(rest)
    lex(rest, [{:at, name} | tokens])
  end

  defp lex(<<char, _rest::binary>> = source, tokens) when letter?(char) do
    {word, rest} = take_word(source)
    lex(rest, [word_token(word) | tokens])
  end

  defp lex(<<a, b, rest::binary>>, tokens) when <<a, b>> in @two_char_ops,
    do: lex(rest, [{:op, <<a, b>>} | tokens])

  defp lex(<<?&, rest::binary>>, tokens), do: lex(rest, [{:op, "&&"} | tokens])
  defp lex(<<?|, rest::binary>>, tokens), do: lex(rest, [{:op, "||"} | tokens])

  defp lex(<<char, rest::binary>>, tokens) when <<char>> in @one_char_ops,
    do: lex(rest, [{:op, <<char>>} | tokens])

  defp lex(<<_skipped, rest::binary>>, tokens), do: lex(rest, tokens)

  # A minus right after a value is subtraction: `[1 -2]` is `1 - 2`. A `}`
  # does not count as a value here, so `{a: 1} -2` gives the number -2.
  defp after_value?([{kind, _value} | _rest])
       when kind in [:number, :string, :ident, :state, :at, :literal],
       do: true

  defp after_value?([{:string, _value, :unterminated} | _rest]), do: true
  defp after_value?([{:op, closer} | _rest]) when closer in [")", "]"], do: true
  defp after_value?(_tokens), do: false

  defp number(source, tokens) do
    {sign, unsigned} =
      case source do
        <<?-, rest::binary>> -> {"-", rest}
        _ -> {"", source}
      end

    {integer, rest} = take_digits(unsigned)

    {fraction, rest} =
      case rest do
        <<?., next, after_dot::binary>> when digit?(next) ->
          take_digits(<<next, after_dot::binary>>)

        _ ->
          {"", rest}
      end

    {exponent, rest} = exponent(rest)
    lex(rest, [{:number, number_value(sign, integer, fraction, exponent)} | tokens])
  end

  defp exponent(<<marker, rest::binary>>) when marker in [?e, ?E] do
    {sign, rest} =
      case rest do
        <<char, after_sign::binary>> when char in [?+, ?-] -> {<<char>>, after_sign}
        _ -> {"", rest}
      end

    {digits, rest} = take_digits(rest)
    {if(digits == "", do: "", else: sign <> digits), rest}
  end

  defp exponent(rest), do: {"", rest}

  defp number_value(sign, integer, fraction, exponent) do
    fraction = if fraction == "", do: "0", else: fraction
    exponent = if exponent == "", do: "0", else: exponent

    case Float.parse("#{sign}#{integer}.#{fraction}e#{exponent}") do
      {value, ""} -> Value.normalize_number(value)
      :error -> 0
    end
  end

  defp take_digits(source) do
    size = count_digits(source, 0)
    <<digits::binary-size(size), rest::binary>> = source
    {digits, rest}
  end

  defp take_word(source) do
    size = count_word(source, 0)
    <<word::binary-size(size), rest::binary>> = source
    {word, rest}
  end

  defp count_digits(<<char, rest::binary>>, count) when digit?(char),
    do: count_digits(rest, count + 1)

  defp count_digits(_source, count), do: count

  defp count_word(<<char, rest::binary>>, count) when word_char?(char),
    do: count_word(rest, count + 1)

  defp count_word(_source, count), do: count

  defp word_token("true"), do: {:literal, true}
  defp word_token("false"), do: {:literal, false}
  defp word_token("null"), do: {:literal, nil}
  defp word_token(word), do: {:ident, word}

  # Double-quoted strings use JSON escapes. When JSON cannot read the text (a
  # raw newline, an escape cut mid-stream) the raw text between the quotes is
  # kept, as the reference implementation does.
  defp double_quoted(source) do
    {size, closed?} = double_quoted_size(source, 1)
    <<raw::binary-size(size), rest::binary>> = source
    json = if closed?, do: raw, else: raw <> "\""

    value =
      case JSON.decode(json) do
        {:ok, value} when is_binary(value) -> value
        _ -> raw |> String.replace_prefix("\"", "") |> strip_closing_quote(closed?)
      end

    value = String.replace_invalid(value)
    token = if closed?, do: {:string, value}, else: {:string, value, :unterminated}
    {token, rest}
  end

  defp strip_closing_quote(text, true), do: String.replace_suffix(text, "\"", "")
  defp strip_closing_quote(text, false), do: text

  defp double_quoted_size(source, offset) do
    case source do
      <<_::binary-size(offset), ?\\, _escaped, _::binary>> ->
        double_quoted_size(source, offset + 2)

      <<_::binary-size(offset), ?\\>> ->
        {offset + 1, false}

      <<_::binary-size(offset), ?", _::binary>> ->
        {offset + 1, true}

      <<_::binary-size(offset), _char, _::binary>> ->
        double_quoted_size(source, offset + 1)

      _ ->
        {offset, false}
    end
  end

  # Text cut inside a multibyte character would carry stray bytes into the
  # program and break anything that encodes it; they become U+FFFD.
  defp text(acc), do: acc |> IO.iodata_to_binary() |> String.replace_invalid()

  defp single_quoted(<<>>, acc), do: {{:string, text(acc), :unterminated}, <<>>}
  defp single_quoted(<<?', rest::binary>>, acc), do: {{:string, text(acc)}, rest}
  defp single_quoted(<<?\\, ?n, rest::binary>>, acc), do: single_quoted(rest, [acc, ?\n])
  defp single_quoted(<<?\\, ?t, rest::binary>>, acc), do: single_quoted(rest, [acc, ?\t])
  defp single_quoted(<<?\\, char, rest::binary>>, acc), do: single_quoted(rest, [acc, char])
  defp single_quoted(<<?\\>>, acc), do: single_quoted(<<>>, acc)
  defp single_quoted(<<char, rest::binary>>, acc), do: single_quoted(rest, [acc, char])
end
