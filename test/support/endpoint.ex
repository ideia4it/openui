defmodule OpenUI.Test.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :openui

  socket("/live", Phoenix.LiveView.Socket)
end
