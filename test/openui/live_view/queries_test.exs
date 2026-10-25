defmodule OpenUI.LiveView.QueriesTest do
  use OpenUI.LiveCase, async: true

  @row_count_program ~s|root = Stack([Metric("n", @Count(t.rows))])\nt = Query("list", {}, {rows: []})|

  test "runs queries after the stream ends and shows loading until the data arrives" do
    test_pid = self()

    tools = %{
      "list" => fn _args ->
        send(test_pid, {:called, self()})

        receive do
          :go -> {:ok, %{"rows" => [1, 2]}}
        end
      end
    }

    view =
      mount_program(
        ~s|root = Stack([Metric("n", @Count(t.rows))])\nt = Query("list", {}, {rows: []})|,
        tools: tools
      )

    assert_receive {:called, task}
    assert render(view) =~ ~s|data-loading="true"|
    send(task, :go)
    assert render_async(view) =~ ~s|data-value="2"|
  end

  test "keeps one refresh timer per query after its arguments change" do
    test_pid = self()

    tools = %{
      "list" => fn args ->
        send(test_pid, {:called, self(), args})

        receive do
          :go -> {:ok, %{"rows" => [args["status"]]}}
        end
      end
    }

    view =
      mount_program(
        ~S"""
        $status = "open"
        root = Stack([Input("status", "Status", $status), Metric("n", @Count(t.rows))])
        t = Query("list", {status: $status}, {rows: []}, 0.3)
        """,
        tools: tools
      )

    assert_receive {:called, first, %{"status" => "open"}}
    send(first, :go)
    render_async(view)

    view
    |> element("#program-p form")
    |> render_change(%{
      "_target" => ["openui", "0.children.0"],
      "openui" => %{"0.children.0" => "closed"}
    })

    assert_receive {:called, second, %{"status" => "closed"}}
    send(second, :go)
    render_async(view)

    assert_receive {:called, refreshed, %{"status" => "closed"}}, 1_000
    send(refreshed, :go)
    refute_receive {:called, _task, _args}, 200
  end

  test "keeps the newest result when an older one arrives late" do
    test_pid = self()

    tools = %{
      "list" => fn %{"status" => status} ->
        send(test_pid, {:called, status, self()})

        receive do
          :go -> {:ok, %{"rows" => List.duplicate(status, String.length(status))}}
        end
      end
    }

    view =
      mount_program(
        ~S"""
        $status = "open"
        root = Stack([filter, Metric("n", @Count(t.rows))])
        filter = Input("status", "S", $status)
        t = Query("list", {status: $status}, {rows: []})
        """,
        tools: tools
      )

    assert_receive {:called, "open", first}

    view
    |> element("#program-p form")
    |> render_change(%{
      "_target" => ["openui", "0.children.0"],
      "openui" => %{"0.children.0" => "closed"}
    })

    assert_receive {:called, "closed", second}
    finish_task(second)
    assert render(view) =~ ~s|data-value="6"|
    finish_task(first)
    assert render(view) =~ ~s|data-value="6"|
  end

  # A local send lands in the mailbox at once, so once the task is gone its
  # result is already queued at the LiveView, ahead of the next render call.
  defp finish_task(task) do
    ref = Process.monitor(task)
    send(task, :go)
    assert_receive {:DOWN, ^ref, :process, ^task, _reason}
  end

  test "a tool that raises becomes a query error and the page stays up" do
    tools = fn "list", _args -> raise "database down" end

    view =
      mount_program(
        ~s|root = Stack([Metric("n", @Count(t.rows))])\nt = Query("list", {}, {rows: []})|,
        tools: tools
      )

    render_async(view)
    assert_receive {:openui, "p", {:errors, [%OpenUI.Error{code: "tool-error", source: :query}]}}
    assert render(view) =~ ~s|data-value="0"|
  end

  test "a tool that returns an error becomes a query error with its reason" do
    view =
      mount_program(@row_count_program,
        tools: %{"list" => fn _args -> {:error, "database down"} end}
      )

    render_async(view)

    assert_receive {:openui, "p",
                    {:errors,
                     [
                       %OpenUI.Error{
                         code: "tool-error",
                         message: ~s(Tool "list" failed: database down)
                       }
                     ]}}

    assert render(view) =~ ~s|data-value="0"|
  end

  @tag :capture_log
  test "a tool that exits becomes a query error and the page stays up" do
    view = mount_program(@row_count_program, tools: %{"list" => fn _args -> exit(:timeout) end})

    render_async(view)

    assert_receive {:openui, "p",
                    {:errors,
                     [
                       %OpenUI.Error{
                         code: "tool-error",
                         message: ~s(Tool "list" failed: {:exit, :timeout})
                       }
                     ]}}

    assert render(view) =~ ~s|data-value="0"|
  end

  test "a tool that answers with bare data counts as a success" do
    view =
      mount_program(@row_count_program,
        tools: %{"list" => fn _args -> %{"rows" => [1, 2, 3]} end}
      )

    assert render_async(view) =~ ~s|data-value="3"|
    refute_receive {:openui, "p", {:errors, _errors}}
  end

  test "a query whose tool the provider lacks reports the tools it has" do
    tools = %{"tickets" => fn _args -> {:ok, %{}} end, "agents" => fn _args -> {:ok, %{}} end}
    view = mount_program(@row_count_program, tools: tools)

    render_async(view)

    assert_receive {:openui, "p",
                    {:errors,
                     [
                       %OpenUI.Error{
                         code: "tool-not-found",
                         hint: "Available tools: agents, tickets"
                       }
                     ]}}
  end

  test "a query on a page without a tool provider reports that no tool is available" do
    view = mount_program(@row_count_program)

    render_async(view)

    assert_receive {:openui, "p",
                    {:errors,
                     [%OpenUI.Error{code: "tool-not-found", hint: "No tools are available"}]}}
  end

  test "a new program stops the refreshes of the program it replaces" do
    test_pid = self()

    tools = %{
      "list" => fn _args ->
        send(test_pid, {:called, self()})

        receive do
          :go -> {:ok, %{"rows" => [1]}}
        end
      end
    }

    view =
      mount_program(
        ~s|root = Stack([Metric("n", @Count(t.rows))])\nt = Query("list", {}, {rows: []}, 0.3)|,
        tools: tools
      )

    assert_receive {:called, first}
    send(first, :go)
    render_async(view)

    send(view.pid, {:set_response, @row_count_program, false})

    assert_receive {:called, replacement}
    send(replacement, :go)
    render_async(view)

    refute_receive {:called, _task}, 500
  end

  test "runs a mutation from a button and continues the plan on success" do
    tools = %{"create" => fn %{"title" => "Bug"} -> {:ok, %{"id" => 7}} end}

    view =
      mount_program(
        ~S"""
        $title = "Bug"
        root = Stack([create])
        m = Mutation("create", {title: $title})
        create = Button("Create", Action([@Run(m), @ToAssistant("Created")]))
        """,
        tools: tools
      )

    view |> element("button[phx-value-key='0.children.0']") |> render_click()
    render_async(view)
    assert_receive {:openui, "p", %OpenUI.Event{human_friendly_message: "Created"}}
  end
end
