defmodule OpenUI.LiveView.HTMLTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias OpenUI.LiveView.HTML
  alias OpenUI.Test.ExampleUI

  defp runtime(source) do
    library = OpenUI.Test.ExampleLibrary

    {runtime, _effects} =
      library
      |> OpenUI.Runtime.new(
        fields: ExampleUI.__openui__(:fields),
        forms: ExampleUI.__openui__(:forms)
      )
      |> OpenUI.Runtime.load(OpenUI.Parser.parse(source, library))

    {runtime, _effects} = OpenUI.Runtime.finish(runtime)
    runtime
  end

  defp html(safe), do: Phoenix.HTML.safe_to_string(safe)

  test "renders nested host components, bindings and action attributes" do
    runtime =
      runtime(~S"""
      $q = "late"
      root = Stack([Card("Tickets", [Input("q", "Search", $q), Button("Go", @ToAssistant("Go"))])])
      """)

    {safe, []} = HTML.render(runtime, ExampleUI, target: 1, dom_id: "p")
    doc = LazyHTML.from_fragment(html(safe))

    assert LazyHTML.attribute(
             LazyHTML.query(doc, "input[name='openui[0.children.0.children.0]']"),
             "value"
           ) ==
             ["late"]

    assert LazyHTML.attribute(
             LazyHTML.query(doc, "button[phx-click='openui:action']"),
             "phx-value-prop"
           ) ==
             ["action"]
  end

  test "drops a host component that raises, reports it and logs the stacktrace" do
    runtime = runtime(~s|root = Stack([Text("ok"), boom])\nboom = Highlight(Card("x"))|)

    log =
      capture_log(fn ->
        {safe, [error]} = HTML.render(runtime, OpenUI.Test.RaisingUI, target: 1, dom_id: "p")
        assert html(safe) =~ "ok"

        assert %OpenUI.Error{code: "runtime-error", statement_id: "boom", component: "Highlight"} =
                 error
      end)

    assert log =~ "Highlight"
  end

  test "reports a catalog component that renders a live component" do
    runtime = runtime(~S|root = Stack([Highlight(Card("x"))])|)

    capture_log(fn ->
      {_safe, [error]} = HTML.render(runtime, OpenUI.Test.LiveComponentUI, target: 1, dom_id: "p")
      assert error.message == "catalog component Highlight cannot render a live component"
    end)
  end

  test "shows the unknown slot where an unknown component was" do
    runtime = runtime(~S|root = Stack([Text("a"), Pie(1)])|)
    unknown = fn error -> Phoenix.HTML.raw(~s(<p class="unknown">#{error.code}</p>)) end

    {safe, _errors} =
      HTML.render(runtime, ExampleUI, target: 1, dom_id: "p", unknown: unknown)

    assert html(safe) =~ ~s(<p class="unknown">unknown-component</p>)
  end
end
