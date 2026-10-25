defmodule OpenUI.Message do
  @moduledoc """
  The protocol a host stores responses with (prompt.md, section 7): the
  program wrapped in `]]>openui:content`, `]]>openui:context` and
  `]]>openui:end` marker lines. The model never writes or sees these lines.

      raw = OpenUI.Message.build(content: program, context: [state], end: true)
      %OpenUI.Message{content: program} = OpenUI.Message.parse(raw)

  When a response was regenerated, the last `content` wins.
  """

  defstruct content: "", context: nil, attributes: %{}, end?: false

  @type t :: %__MODULE__{
          content: String.t(),
          context: term(),
          attributes: %{String.t() => String.t()},
          end?: boolean()
        }

  @prefix "]]>openui:"
  @marker ~r/^\]\]>openui:([a-z]+)(?:\?(.*))?$/
  # A regenerated response writes its content line right after the cut-off
  # text of the failed one; it starts a line there so the last content wins.
  @retry ~r/([^\n])(?=\]\]>openui:content(?:\?|\r?\n|$))/
  @retry_cut ~r/[^\n](\]\]>[a-z:]*)$/

  @doc """
  Reads a stored message. With `streaming: true`, a last line that may be a
  marker cut mid-stream is held back.
  """
  @spec parse(String.t(), keyword()) :: t()
  def parse(raw, opts \\ []) when is_binary(raw) do
    %{content: content, context: context, attributes: attributes, end?: end?} = read(raw, opts)

    %__MODULE__{
      content: content,
      context: decode_context(context),
      attributes: attributes,
      end?: end?
    }
  end

  @doc """
  Writes a stored message. `context` is written as is when it is a string,
  else as JSON, and is left out when `nil`. `attributes` are key-value pairs,
  such as `[{"library", "support@1.2.0"}]`.
  """
  @spec build(keyword()) :: String.t()
  def build(opts) do
    content = Keyword.fetch!(opts, :content)

    query =
      Enum.map_join(Keyword.get(opts, :attributes, []), "&", fn {key, value} ->
        encode(key) <> "=" <> encode(value)
      end)

    message =
      @prefix <> "content" <> if(query == "", do: "", else: "?" <> query) <> "\n" <> content

    message =
      case Keyword.get(opts, :context) do
        nil -> message
        context when is_binary(context) -> message <> "\n" <> @prefix <> "context\n" <> context
        context -> message <> "\n" <> @prefix <> "context\n" <> OpenUI.JSON.encode!(context)
      end

    if Keyword.get(opts, :end, false), do: message <> "\n" <> @prefix <> "end", else: message
  end

  @doc """
  The stored turn for an action that continues the conversation, in the
  reference format: the message, and as context
  `["User clicked: <message>", formState, context]` (the context only when
  the action has one).
  """
  @spec from_event(OpenUI.Event.t()) :: String.t()
  def from_event(%OpenUI.Event{} = event) do
    message = event.human_friendly_message
    extra = if Map.has_key?(event.params, "context"), do: [event.params["context"]], else: []
    build(content: message, context: ["User clicked: " <> message, event.form_state | extra])
  end

  @doc """
  What the model reads of a stored message, with every marker line removed:
  the program for an assistant turn; for a user turn, the message and, when
  there is a context, `context and form values = <its JSON>`.
  """
  @spec model_text(String.t(), :assistant | :user) :: String.t()
  def model_text(raw, :assistant), do: read(raw, []).content

  def model_text(raw, :user) do
    case read(raw, []) do
      %{content: content, context: nil} ->
        content

      %{content: content, context: context} ->
        content <> "\ncontext and form values = " <> context
    end
  end

  defp read(raw, opts) do
    text = Regex.replace(@retry, raw, "\\1\n")
    streaming? = Keyword.get(opts, :streaming, false)
    text = if streaming?, do: hold_back_cut_marker(text), else: text
    lines = String.split(text, "\n")
    last = List.last(lines)

    held? =
      streaming? and last != "" and
        (String.starts_with?(last, @prefix) or String.starts_with?(@prefix, last))

    lines = if held?, do: Enum.drop(lines, -1), else: lines

    {sections, end_at} = sections(lines)
    sections = if held?, do: close_last(sections), else: sections
    kinds = Enum.map(sections, & &1.kind)
    winner = max(0, last_index(kinds, "content"))
    context_at = last_index(kinds, "context")
    winning = Enum.at(sections, winner)

    %{
      content: body(winning),
      context: if(context_at > winner, do: sections |> Enum.at(context_at) |> body()),
      attributes: winning.attributes,
      end?: end_at >= winner
    }
  end

  defp hold_back_cut_marker(text) do
    case Regex.run(@retry_cut, text, return: :index) do
      [{start, _length}, {marker_start, marker_length}] ->
        if String.starts_with?(
             @prefix <> "content",
             binary_part(text, marker_start, marker_length)
           ),
           do: binary_part(text, 0, start + 1),
           else: text

      nil ->
        text
    end
  end

  # Sections in order, the first holding the text before any marker. An `end`
  # line is remembered by the index of the section it closes; text after it
  # stays with that section.
  defp sections(lines) do
    initial = {[%{kind: nil, attributes: %{}, lines: []}], -1}
    count = length(lines)

    lines
    |> Enum.with_index()
    |> Enum.reduce_while(initial, fn {line, index}, acc ->
      line
      |> String.trim_trailing("\r")
      |> then(&Regex.run(@marker, &1))
      |> add_line(line, index == count - 2 and Enum.at(lines, index + 1) == "", acc)
    end)
  end

  defp add_line(nil, line, _before_last_empty_line?, {sections, end_at}),
    do: {:cont, {append_line(sections, line), end_at}}

  # Writers end a message with the end line; an empty line after it is the
  # end of the text.
  defp add_line(
         [_line, "end" | _attributes],
         _line_text,
         before_last_empty_line?,
         {sections, _end_at}
       ) do
    sections = close_last(sections)
    acc = {sections, length(sections) - 1}
    if before_last_empty_line?, do: {:halt, acc}, else: {:cont, acc}
  end

  defp add_line(
         [_line, kind | attributes],
         _line_text,
         _before_last_empty_line?,
         {sections, end_at}
       ) do
    section = %{kind: kind, attributes: read_attributes(List.first(attributes, "")), lines: []}
    {:cont, {close_last(sections) ++ [section], end_at}}
  end

  defp append_line(sections, line) do
    List.update_at(sections, -1, fn section -> %{section | lines: section.lines ++ [line]} end)
  end

  # The newline (and its \r) before a marker is not part of the body.
  defp close_last(sections) do
    List.update_at(sections, -1, fn
      %{lines: []} = section ->
        section

      section ->
        %{section | lines: List.update_at(section.lines, -1, &String.trim_trailing(&1, "\r"))}
    end)
  end

  defp body(section), do: Enum.join(section.lines, "\n")

  defp last_index(kinds, kind) do
    case kinds
         |> Enum.with_index()
         |> Enum.filter(fn {item, _index} -> item == kind end)
         |> List.last() do
      {_kind, index} -> index
      nil -> -1
    end
  end

  defp decode_context(nil), do: nil

  # The context is JSON defined by the host; anything else stays raw text.
  defp decode_context(text) do
    case JSON.decode(text) do
      {:ok, value} -> value
      {:error, _reason} -> text
    end
  end

  defp read_attributes(""), do: %{}

  # Readers decode like URLSearchParams: an unencoded @, or a % that starts
  # no escape, reads as written.
  defp read_attributes(query) do
    for pair <- String.split(query, "&"),
        [key | value] = String.split(pair, "=", parts: 2),
        key = URI.decode_www_form(key),
        key != "",
        into: %{},
        do: {key, URI.decode_www_form(List.first(value, ""))}
  end

  # The bytes of URLSearchParams: encodeURIComponent with !'()~ escaped too,
  # and a space as "+".
  defp encode(string) do
    string
    |> URI.encode(&(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 in [?-, ?_, ?., ?*]))
    |> String.replace("%20", "+")
  end
end
