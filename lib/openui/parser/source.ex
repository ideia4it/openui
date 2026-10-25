defmodule OpenUI.Parser.Source do
  @moduledoc """
  Prepares response text for parsing (language.md, section 1.2): fence
  extraction, comment stripping and trimming, in that order.
  """

  @fence "```"

  @doc "Returns the program text inside a response."
  @spec prepare(String.t()) :: String.t()
  def prepare(text) when is_binary(text) do
    text
    |> String.trim()
    |> extract_fences()
    |> strip_comments()
    |> String.trim()
  end

  # A fence opens only with three backticks at the start of a line (after
  # optional indentation). Text outside fences is prose and is ignored.
  defp extract_fences(text) do
    case fence_blocks(text, []) do
      [] -> text
      blocks -> Enum.join(blocks, "\n")
    end
  end

  defp fence_blocks(text, blocks) do
    case next_opening(text) do
      nil ->
        Enum.reverse(blocks)

      after_opening ->
        {block, rest} = fence_body(after_opening)
        fence_blocks(rest, [block | blocks])
    end
  end

  defp next_opening(text) do
    case Regex.run(~r/^[ \t]*```[^\n]*(?:\n|\z)/m, text, return: :index) do
      [{start, length}] -> binary_part(text, start + length, byte_size(text) - start - length)
      nil -> nil
    end
  end

  # Inside a fence, a backtick run inside a double-quoted string does not close
  # it; single quotes do not shield. An unterminated fence runs to the end.
  defp fence_body(text), do: fence_body(text, 0, false)

  defp fence_body(text, offset, in_string?) do
    case text do
      <<_::binary-size(offset)>> ->
        {text, ""}

      <<body::binary-size(offset), @fence, rest::binary>> when not in_string? ->
        {body, rest}

      <<_::binary-size(offset), ?\\, _escaped, _::binary>> when in_string? ->
        fence_body(text, offset + 2, true)

      <<_::binary-size(offset), ?", _::binary>> ->
        fence_body(text, offset + 1, not in_string?)

      _ ->
        fence_body(text, offset + 1, in_string?)
    end
  end

  # `//` and `#` start a comment that runs to the end of the line. Markers
  # inside strings, multi-line strings included, are not comments.
  defp strip_comments(text) do
    {lines, _quote} =
      text
      |> String.split("\n")
      |> Enum.map_reduce(nil, &strip_line_comment(&1, &2, 0))

    Enum.join(lines, "\n")
  end

  defp strip_line_comment(line, quote, offset) do
    case {line, quote} do
      {<<_::binary-size(offset)>>, _quote} ->
        {line, quote}

      {<<_::binary-size(offset), ?\\, _escaped, _::binary>>, quote} when quote != nil ->
        strip_line_comment(line, quote, offset + 2)

      {<<_::binary-size(offset), char, _::binary>>, quote} when quote != nil ->
        strip_line_comment(line, if(char == quote, do: nil, else: quote), offset + 1)

      {<<_::binary-size(offset), char, _::binary>>, nil} when char in [?", ?'] ->
        strip_line_comment(line, char, offset + 1)

      {<<code::binary-size(offset), "//", _::binary>>, nil} ->
        {String.trim_trailing(code), nil}

      {<<code::binary-size(offset), ?#, _::binary>>, nil} ->
        {String.trim_trailing(code), nil}

      _ ->
        strip_line_comment(line, quote, offset + 1)
    end
  end
end
