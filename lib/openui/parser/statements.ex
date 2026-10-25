defmodule OpenUI.Parser.Statements do
  @moduledoc """
  Statement boundaries (language.md, section 1.4) and implicit closing
  (section 4, rule 2).

  The batch parser, the stream and the edit merge all split with `split/2`,
  which is what keeps their boundaries identical byte for byte.
  """

  @doc """
  Splits prepared text into statement texts.

  A statement ends at a newline outside brackets and strings, unless a
  ternary is open or the next line starts with `?`. With `final: false` the
  text may still grow, so a statement completes only once the next line's
  first non-whitespace character has arrived; the rest is returned as
  `pending`. With `final: true` everything completes.
  """
  @spec split(String.t(), keyword()) :: {[String.t()], String.t()}
  def split(text, opts) when is_binary(text) do
    scan(text, %{
      offset: 0,
      start: 0,
      depth: 0,
      ternaries: 0,
      dangling?: false,
      quote: nil,
      final?: Keyword.fetch!(opts, :final),
      completed: []
    })
  end

  @doc """
  Closes an unterminated string (adding a backslash first when the text ends
  mid-escape), then unclosed brackets in reverse order. A closing bracket that
  does not match the open one is skipped. Returns the closed text and whether
  anything had to be closed.
  """
  @spec auto_close(String.t()) :: {String.t(), boolean()}
  def auto_close(text) when is_binary(text) do
    {quote, escaping?, stack} = open_constructs(text, nil, false, [])

    if quote == nil and stack == [],
      do: {text, false},
      else:
        {IO.iodata_to_binary([text, string_closer(quote, escaping?), Enum.map(stack, &closer/1)]),
         true}
  end

  defp string_closer(nil, _escaping?), do: []
  defp string_closer(quote, true), do: ["\\", quote]
  defp string_closer(quote, false), do: [quote]

  defp scan(text, %{offset: offset} = state) when offset >= byte_size(text),
    do: finish(text, state)

  defp scan(text, %{quote: quote} = state) when quote != nil do
    case binary_part(text, state.offset, 1) do
      "\\" -> scan(text, %{state | offset: state.offset + 2})
      <<^quote>> -> scan(text, %{state | offset: state.offset + 1, quote: nil})
      _ -> scan(text, %{state | offset: state.offset + 1})
    end
  end

  defp scan(text, state), do: step(text, :binary.at(text, state.offset), state)

  defp step(text, char, state) when char in [?", ?'],
    do: scan(text, %{advance(state) | quote: char, dangling?: false})

  defp step(text, char, state) when char in [?(, ?[, ?{],
    do: scan(text, %{advance(state) | depth: state.depth + 1, dangling?: false})

  defp step(text, char, state) when char in [?), ?], ?}],
    do: scan(text, %{advance(state) | depth: max(state.depth - 1, 0), dangling?: false})

  defp step(text, ??, %{depth: 0} = state),
    do: scan(text, %{advance(state) | ternaries: state.ternaries + 1, dangling?: true})

  defp step(text, ?:, %{depth: 0, ternaries: ternaries} = state) when ternaries > 0,
    do: scan(text, %{advance(state) | ternaries: ternaries - 1, dangling?: true})

  defp step(text, ?\n, state), do: newline(text, state)
  defp step(text, char, state) when char in [?\s, ?\t, ?\r], do: scan(text, advance(state))
  defp step(text, _char, state), do: scan(text, %{advance(state) | dangling?: false})

  defp advance(state), do: %{state | offset: state.offset + 1}

  defp newline(text, state) do
    advance = %{state | offset: state.offset + 1}

    if state.depth > 0 or state.ternaries > 0 or state.dangling? do
      scan(text, advance)
    else
      case next_significant(text, state.offset + 1) do
        nil when not state.final? ->
          pending(text, state)

        "?" ->
          scan(text, advance)

        _ ->
          scan(text, %{
            complete(text, state, state.offset)
            | offset: state.offset + 1,
              start: state.offset + 1
          })
      end
    end
  end

  defp next_significant(text, offset) do
    case Regex.run(~r/[^ \t\r\n]/, text, return: :index, offset: offset) do
      [{index, 1}] -> binary_part(text, index, 1)
      nil -> nil
    end
  end

  defp complete(text, state, stop) do
    statement = text |> binary_part(state.start, stop - state.start) |> String.trim()
    if statement == "", do: state, else: %{state | completed: [statement | state.completed]}
  end

  defp finish(text, %{final?: true} = state) do
    state = complete(text, state, byte_size(text))
    {Enum.reverse(state.completed), ""}
  end

  defp finish(text, state), do: pending(text, state)

  defp pending(text, state) do
    {Enum.reverse(state.completed), binary_part(text, state.start, byte_size(text) - state.start)}
  end

  defp open_constructs(<<>>, quote, escaping?, stack), do: {quote, escaping?, stack}

  defp open_constructs(<<_char, rest::binary>>, quote, true, stack),
    do: open_constructs(rest, quote, false, stack)

  defp open_constructs(<<?\\, rest::binary>>, quote, false, stack) when quote != nil,
    do: open_constructs(rest, quote, true, stack)

  defp open_constructs(<<char, rest::binary>>, quote, false, stack) when quote != nil,
    do: open_constructs(rest, if(char == quote, do: nil, else: quote), false, stack)

  defp open_constructs(<<char, rest::binary>>, nil, false, stack) when char in [?", ?'],
    do: open_constructs(rest, char, false, stack)

  defp open_constructs(<<char, rest::binary>>, nil, false, stack) when char in [?(, ?[, ?{],
    do: open_constructs(rest, nil, false, [char | stack])

  defp open_constructs(<<char, rest::binary>>, nil, false, [open | stack] = open_stack)
       when char in [?), ?], ?}] do
    if closer(open) == <<char>>,
      do: open_constructs(rest, nil, false, stack),
      else: open_constructs(rest, nil, false, open_stack)
  end

  defp open_constructs(<<_char, rest::binary>>, nil, false, stack),
    do: open_constructs(rest, nil, false, stack)

  defp closer(?(), do: ")"
  defp closer(?[), do: "]"
  defp closer(?{), do: "}"
end
