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
           } = Message.parse(raw, [])
  end

  test "uses text before any marker as content and holds back a cut marker while streaming" do
    assert Message.parse("root = Stack([])", []).content == "root = Stack([])"

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
end
