:openui_test_tools = :ets.new(:openui_test_tools, [:named_table, :public, read_concurrency: true])
{:ok, _supervisor} = Supervisor.start_link([OpenUI.Test.Endpoint], strategy: :one_for_one)
ExUnit.start()
