defmodule OpenUI.MessageTest do
  use ExUnit.Case, async: true

  alias OpenUI.Message

  test "writes the stored form with encoded attributes, context and end" do
    assert Message.build(
             content: "root = Stack([])",
             context: %{"formState" => %{"note" => "rush"}},
             attributes: [{"library", "support@1.2.0"}, {"note", "a b!"}],
             end: true
           ) ==
             "]]>openui:content?library=support%401.2.0&note=a+b%21\nroot = Stack([])\n" <>
               "]]>openui:context\n{\"formState\":{\"note\":\"rush\"}}\n]]>openui:end"
  end

  test "reads the last content, its attributes, context and end flag" do
    raw =
      "ignored\n]]>openui:content?library=x%401\nold\n]]>openui:context\n[1]\n" <>
        "cut]]>openui:content?library=support@1.2.0&libraryVersion=2\nroot = Stack([])\n" <>
        "]]>openui:debug\nnoise\n]]>openui:context\nnot json\n]]>openui:end"

    assert %Message{
             content: "root = Stack([])",
             context: "not json",
             end?: true,
             attributes: %{"library" => "support@1.2.0", "libraryVersion" => "2"}
           } = Message.parse(raw)
  end

  test "uses text before any marker as content and holds back a cut marker while streaming" do
    assert Message.parse("root = Stack([])").content == "root = Stack([])"

    assert Message.parse("]]>openui:content\nroot = Stack([])\n]]>openui:con", streaming: true).content ==
             "root = Stack([])"
  end

  test "builds what the model reads for each side of the conversation" do
    raw =
      Message.from_event(%OpenUI.Event{
        type: "continue_conversation",
        human_friendly_message: "Save",
        params: %{"context" => %{"id" => 7}},
        form_state: %{"note" => "rush"}
      })

    assert Message.model_text(raw, :user) ==
             ~s|Save\ncontext and form values = ["User clicked: Save",{"note":"rush"},{"id":7}]|

    assert Message.model_text("]]>openui:content\nroot = Stack([])\n]]>openui:end", :assistant) ==
             "root = Stack([])"
  end

  test "writes a turn without context, or with a text context as it is" do
    plain = Message.build(content: "Show open tickets")

    assert plain == "]]>openui:content\nShow open tickets"
    assert Message.model_text(plain, :user) == "Show open tickets"

    noted = Message.build(content: "Show open tickets", context: "from the sidebar")

    assert noted == "]]>openui:content\nShow open tickets\n]]>openui:context\nfrom the sidebar"

    assert Message.model_text(noted, :user) ==
             "Show open tickets\ncontext and form values = from the sidebar"
  end

  test "while streaming, holds back a content marker cut right after the text of a failed response" do
    raw = "]]>openui:content\nroot = Stack([a])\na = Ca]]>openui:cont"

    assert Message.parse(raw, streaming: true).content == "root = Stack([a])\na = Ca"

    assert Message.parse(raw <> "ent\nroot = Stack([])", streaming: true).content ==
             "root = Stack([])"
  end

  test "while streaming, keeps program text that only looks like the start of a marker" do
    raw = "]]>openui:content\nroot = Text(\"x]]>end"

    assert Message.parse(raw, streaming: true).content == "root = Text(\"x]]>end"
  end

  test "keeps an attribute whose percent escape is malformed as it was written" do
    raw = "]]>openui:content?discount=100%\nroot = Stack([])"

    assert Message.parse(raw).attributes == %{"discount" => "100%"}
  end
end
