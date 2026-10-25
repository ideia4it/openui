defmodule OpenUI.ConformanceTest do
  use ExUnit.Case, async: true

  for id <- OpenUI.Conformance.case_ids() do
    test id do
      assert OpenUI.Conformance.run(unquote(id)) == []
    end
  end
end
