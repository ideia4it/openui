import Config

config :phoenix, :json_library, JSON

config :openui, OpenUI.Test.Endpoint,
  secret_key_base: String.duplicate("openui-test-secret-key-base-", 4),
  live_view: [signing_salt: "openui-test"],
  server: false
