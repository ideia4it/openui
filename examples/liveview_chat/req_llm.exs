Mix.install([
  {:openui, path: Path.expand("../..", __DIR__)},
  {:phoenix_playground, "~> 0.1.9"},
  {:req_llm, "~> 1.27"}
])

Code.require_file("catalog.exs", __DIR__)
Code.require_file("chat.exs", __DIR__)

defmodule Support.ReqLLMAssistant do
  alias ReqLLM.Context

  # The model does not call the tools here: it writes Query("list_tickets", ...)
  # and the renderer fetches the data through the tool_provider.
  def answer(transcript, reply_to) do
    system_prompt = OpenUI.Prompt.generate(Support.Library, tools: Support.Tickets.tools())
    context = Context.new([Context.system(system_prompt) | Enum.map(transcript, &message/1)])

    with {:ok, response} <- ReqLLM.stream_text(Support.ChatLive.model!(), context) do
      text =
        response
        |> ReqLLM.StreamResponse.tokens()
        |> Enum.reduce("", fn token, text ->
          text = text <> token
          send(reply_to, {:answer_chunk, text})
          text
        end)

      {:ok, text}
    end
  end

  defp message({:user, text}), do: Context.user(text)
  defp message({:assistant, text}), do: Context.assistant(text)
end

Support.ChatLive.model!()
Application.put_env(:support_example, :assistant, Support.ReqLLMAssistant)
PhoenixPlayground.start(live: Support.ChatLive, open_browser: false)
