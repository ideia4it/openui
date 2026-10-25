defmodule OpenUI.Stream do
  @moduledoc """
  Parses a response a chunk at a time (language.md, section 4).

  After every chunk, `program/1` gives a program that renders: completed
  statements are read once and kept, and the cut-off tail is closed
  implicitly and read again on each chunk. A cut-off statement never replaces
  a completed one with the same name. When the host ends the stream with
  `finish/1`, the program equals a batch parse of the whole text.

      stream =
        MyApp.Library
        |> OpenUI.Stream.new()
        |> OpenUI.Stream.push("root = Stack([title])\\ntitle = Te")

      OpenUI.Stream.program(stream)
  """

  alias OpenUI.{Library, Parser, Program}
  alias OpenUI.Parser.{Source, Statements}

  defstruct [
    :library,
    buffer: "",
    held: "",
    completed_prefix: "",
    completed: [],
    final: nil
  ]

  @type t :: %__MODULE__{
          library: Library.t(),
          buffer: String.t(),
          held: binary(),
          completed_prefix: String.t(),
          completed: [OpenUI.Statement.t()],
          final: Program.t() | nil
        }

  @doc "Starts a stream for a library."
  @spec new(Library.t() | module()) :: t()
  def new(library), do: %__MODULE__{library: Library.resolve(library)}

  @doc """
  Adds the next chunk. A chunk after `finish/1` starts a new stream.
  """
  @spec push(t(), String.t()) :: t()
  def push(%__MODULE__{final: %Program{}} = stream, chunk), do: push(new(stream.library), chunk)

  def push(%__MODULE__{} = stream, chunk) when is_binary(chunk) do
    {text, held} = split_incomplete_character(stream.held <> chunk)
    complete_statements(%{stream | buffer: stream.buffer <> text, held: held})
  end

  @doc "Ends the stream: the cut-off tail completes, as in a batch parse of the whole text."
  @spec finish(t()) :: t()
  def finish(%__MODULE__{final: %Program{}} = stream), do: stream

  def finish(%__MODULE__{} = stream) do
    text = stream.buffer <> stream.held
    %{stream | buffer: text, held: "", final: Parser.parse(text, stream.library)}
  end

  @doc "The text accepted so far."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{buffer: buffer}), do: buffer

  @doc "True once `finish/1` ran."
  @spec finished?(t()) :: boolean()
  def finished?(%__MODULE__{final: final}), do: final != nil

  @doc "The program as of the latest chunk."
  @spec program(t()) :: Program.t()
  def program(%__MODULE__{final: %Program{} = program}), do: program

  def program(%__MODULE__{} = stream) do
    pending_text = pending_text(stream)

    case pending_text != "" && Parser.statement(pending_text) do
      %OpenUI.Statement{} = pending -> build_with_pending(stream, pending)
      _no_pending_statement -> Parser.build(stream.completed, stream.library, final: false)
    end
  rescue
    # Like `OpenUI.Parser.parse/2`, a failure of the parser itself is reported, not raised.
    exception ->
      error = %OpenUI.Error{
        source: :parser,
        code: "parse-exception",
        message: Exception.message(exception)
      }

      %Program{errors: [error]}
  end

  defp build_with_pending(stream, pending) do
    completed_ids = MapSet.new(stream.completed, & &1.id)

    statements =
      if pending.pending? and MapSet.member?(completed_ids, pending.id),
        do: stream.completed,
        else: stream.completed ++ [pending]

    Parser.build(statements, stream.library,
      final: false,
      incomplete: pending.pending?,
      ignore_state: growing_state_name(stream)
    )
  end

  # A $name at the very end of the text may still grow ($d of $dishes), so it
  # is not declared until more text arrives, unless a completed statement
  # already uses it.
  defp growing_state_name(stream) do
    with [name] <- Regex.run(~r/\$\w+$/, stream.buffer),
         false <- Enum.any?(stream.completed, &String.contains?(&1.source, name)) do
      [name]
    else
      _ -> []
    end
  end

  defp complete_statements(stream) do
    prepared = Source.prepare(stream.buffer)

    stream =
      if String.starts_with?(prepared, stream.completed_prefix),
        do: stream,
        else: %{stream | completed_prefix: "", completed: []}

    prefix_size = byte_size(stream.completed_prefix)
    rest = binary_part(prepared, prefix_size, byte_size(prepared) - prefix_size)
    {texts, pending} = Statements.split(rest, final: false)
    new_statements = texts |> Enum.map(&Parser.statement/1) |> Enum.reject(&is_nil/1)
    completed_size = prefix_size + byte_size(rest) - byte_size(pending)

    %{
      stream
      | completed: stream.completed ++ new_statements,
        completed_prefix: binary_part(prepared, 0, completed_size)
    }
  end

  defp pending_text(stream) do
    prepared = Source.prepare(stream.buffer)
    prefix_size = byte_size(stream.completed_prefix)
    prepared |> binary_part(prefix_size, byte_size(prepared) - prefix_size) |> String.trim()
  end

  # A chunk may end inside a multibyte character; those bytes wait for the
  # next chunk.
  defp split_incomplete_character(text) do
    if String.valid?(text) do
      {text, ""}
    else
      Enum.find_value(1..3, {text, ""}, &incomplete_tail(text, &1))
    end
  end

  defp incomplete_tail(text, size) when byte_size(text) < size, do: nil

  defp incomplete_tail(text, size) do
    head_size = byte_size(text) - size
    <<head::binary-size(head_size), tail::binary>> = text
    if String.valid?(head) and character_start?(tail), do: {head, tail}, else: nil
  end

  defp character_start?(<<0b110::3, _::5>>), do: true
  defp character_start?(<<0b1110::4, _::4, rest::binary>>) when byte_size(rest) <= 1, do: true
  defp character_start?(<<0b11110::5, _::3, rest::binary>>) when byte_size(rest) <= 2, do: true
  defp character_start?(_tail), do: false
end
