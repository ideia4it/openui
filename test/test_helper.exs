{:ok, _supervisor} = Supervisor.start_link([OpenUI.Test.Endpoint], strategy: :one_for_one)
ExUnit.start()
