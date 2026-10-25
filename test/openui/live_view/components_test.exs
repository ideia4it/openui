defmodule OpenUI.LiveView.ComponentsTest do
  use ExUnit.Case, async: true

  alias OpenUI.Test.ExampleUI

  test "refuses a components module that misses a catalog component or reuses a reserved assign" do
    assert_raise CompileError, ~r/is missing stack\/1 for catalog component Stack/, fn ->
      Code.compile_string(~S"""
      defmodule MissingUI do
        use OpenUI.LiveView.Components, library: OpenUI.Test.ExampleLibrary
      end
      """)
    end

    assert_raise CompileError, ~r/Card.loading uses the reserved assign name loading/, fn ->
      Code.compile_string(~S"""
      defmodule ReservedLibrary do
        use OpenUI.Library, root: "Card"
        component "Card", description: "x", props: [loading: [type: :boolean]]
      end

      defmodule ReservedUI do
        use OpenUI.LiveView.Components, library: ReservedLibrary
        def card(assigns), do: ~H""
      end
      """)
    end
  end

  test "refuses fields and forms that name a component the catalog lacks" do
    error =
      assert_raise CompileError, fn ->
        Code.compile_string(~S"""
        defmodule UnknownFieldsUI do
          use OpenUI.LiveView.Components,
            library: OpenUI.Test.ExampleLibrary,
            fields: %{"DatePicker" => [name: "name", type: "date"]},
            forms: %{"Wizard" => "title"}
        end
        """)
      end

    assert Exception.message(error) =~ "fields lists DatePicker, which is not in the catalog"
    assert Exception.message(error) =~ "forms lists Wizard, which is not in the catalog"
  end

  test "maps catalog components to the host functions" do
    assert ExampleUI.__openui__({:function, "LineChart"}) == :line_chart
    assert ExampleUI.__openui__(:forms) == %{"Form" => "name"}
  end
end
