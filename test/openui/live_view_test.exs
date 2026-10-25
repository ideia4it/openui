defmodule OpenUI.LiveViewTest do
  use OpenUI.LiveCase, async: true

  import ExUnit.CaptureLog

  test "draws partial frames while streaming and finishes when the stream ends" do
    view = mount_program(~s|root = Stack([Text("Hel|, streaming: true)
    assert render(view) =~ "Hel"
    send(view.pid, {:set_response, ~s|root = Stack([Text("Hello")])|, false})
    assert render(view) =~ "Hello"
  end

  test "keeps a character the stream cut between two updates whole" do
    <<first_byte, _rest::binary>> = "é"
    view = mount_program(~s|root = Stack([Text("caf| <> <<first_byte>>, streaming: true)
    send(view.pid, {:set_response, ~s|root = Stack([Text("café")])|, false})

    assert render(view) =~ "café"
    refute render(view) =~ "�"
  end

  test "typing into a bound field updates the page and tells the host" do
    view =
      mount_program(~S"""
      $q = ""
      root = Stack([Input("q", "Search", $q), Text("You typed: " + $q)])
      """)

    view
    |> element("#program-p form")
    |> render_change(%{
      "_target" => ["openui", "0.children.0"],
      "openui" => %{"0.children.0" => "late"}
    })

    assert render(view) =~ "You typed: late"
    assert_receive {:openui, "p", {:state, %{"$q" => "late"}}}
  end

  test "ignores field values of a shape no form sends" do
    view =
      mount_program(~S"""
      $q = "start"
      root = Stack([Input("q", "Search", $q), Text("You typed: " + $q)])
      """)

    form = element(view, "#program-p form")
    render_change(form, %{"_target" => ["openui", "0.children.0"], "openui" => "oops"})

    render_change(form, %{
      "_target" => ["openui", "0.children.0"],
      "openui" => %{"0.children.0" => %{"x" => "1"}}
    })

    assert render(view) =~ "You typed: start"
    assert has_element?(view, "input[value='start']")
    refute_receive {:openui, "p", {:state, _state}}
  end

  test "a button sends its event to the host with the form state" do
    view =
      mount_program(~S"""
      root = Stack([Form("contact", [Input("email", "E-mail"), send])])
      send = Button("Send", @ToAssistant("Send"))
      """)

    view
    |> element("#program-p form")
    |> render_change(%{
      "_target" => ["openui", "0.children.0.children.0"],
      "openui" => %{"0.children.0.children.0" => "a@b.co"}
    })

    view |> element("button[phx-value-key='0.children.0.children.1']") |> render_click()

    assert_receive {:openui, "p",
                    %OpenUI.Event{
                      human_friendly_message: "Send",
                      form_name: "contact",
                      form_state: %{"contact" => %{"email" => %{"value" => "a@b.co"}}}
                    }}
  end

  test "reopening a stored message restores its state and ignores a context that is not JSON" do
    stored =
      OpenUI.Message.build(
        content: ~s|$q = ""\nroot = Stack([Text("Saved: " + $q)])|,
        context: [%{"$q" => "rush"}],
        end: true
      )

    assert render(mount_program(stored)) =~ "Saved: rush"

    broken =
      "]]>openui:content\nroot = Stack([Text(\"ok\")])\n]]>openui:context\n{not json\n]]>openui:end"

    assert render(mount_program(broken)) =~ "ok"
  end

  test "reports errors when they change and an empty list after recovery" do
    view = mount_program(~S|root = Stack([Pie(1)])|)
    assert_receive {:openui, "p", {:errors, [%OpenUI.Error{code: "unknown-component"}]}}
    send(view.pid, {:set_response, ~S|root = Stack([Text("fixed")])|, false})
    assert render(view) =~ "fixed"
    assert_receive {:openui, "p", {:errors, []}}
  end

  test "survives a broken components module and logs it" do
    log =
      capture_log(fn ->
        view = mount_program(~S|root = Stack([])|, components: NotAComponentsModule)
        assert render(view) =~ ~s|id="program-p"|
      end)

    assert log =~ "NotAComponentsModule"
  end
end
