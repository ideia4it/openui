defmodule OpenUI.Test.ExampleFunctions do
  @moduledoc false

  def percent(%{"part" => part, "total" => total}) when total != 0,
    do: "#{round(part / total * 100)}%"

  def percent(_args), do: "0%"
end
