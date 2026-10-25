if Code.ensure_loaded?(Phoenix.Component) do
  defmodule OpenUI.LiveView.Components do
    @moduledoc """
    Maps a library's components to the host's function components.

        defmodule MyAppWeb.AssistantUI do
          use OpenUI.LiveView.Components,
            library: MyApp.Library,
            fields: %{"Input" => [name: "name", type: "input"]},
            forms: %{"Form" => "name"}

          def line_chart(assigns), do: ~H"..."
        end

    Every catalog component needs a function named after it in snake case
    (`LineChart` is `line_chart/1`), or the module does not compile. `fields`
    names the components that are form fields (the prop that holds the field
    name and the field's component type), and `forms` the components that
    give a form name to their subtree (and the prop that holds it). A form
    component renders a `<fieldset>` or a `<div>`, never a `<form>`: the
    renderer already wraps the program in one.

    The assigns each function receives are described in `OpenUI.LiveView`.
    """

    @reserved_assigns ~w(bind loading error)

    @doc false
    defmacro __using__(opts) do
      quote do
        use Phoenix.Component
        @openui_components_options unquote(opts)
        @before_compile OpenUI.LiveView.Components
      end
    end

    @doc false
    defmacro __before_compile__(env) do
      opts = Module.get_attribute(env.module, :openui_components_options)
      library_module = Keyword.fetch!(opts, :library)
      Code.ensure_compiled!(library_module)
      library = OpenUI.Library.resolve(library_module)
      fields = Map.new(Keyword.get(opts, :fields, %{}))
      forms = Map.new(Keyword.get(opts, :forms, %{}))
      functions = Map.new(library.components, &{&1.name, function_name(&1.name)})

      case problems(env.module, library, functions, fields, forms) do
        [] ->
          quote do
            @doc false
            def __openui__(:library), do: unquote(library_module)
            def __openui__(:fields), do: unquote(Macro.escape(fields))
            def __openui__(:forms), do: unquote(Macro.escape(forms))
            def __openui__({:function, name}), do: Map.get(unquote(Macro.escape(functions)), name)
          end

        problems ->
          raise CompileError,
            description: Enum.join(problems, "; "),
            file: env.file,
            line: env.line
      end
    end

    defp function_name(component), do: component |> Macro.underscore() |> String.to_atom()

    defp problems(module, library, functions, fields, forms) do
      names = Enum.map(library.components, & &1.name)

      missing =
        for component <- library.components,
            fun = functions[component.name],
            not Module.defines?(module, {fun, 1}),
            do: "#{inspect(module)} is missing #{fun}/1 for catalog component #{component.name}"

      reserved =
        for component <- library.components,
            prop <- component.props,
            prop.name in @reserved_assigns,
            do: "#{component.name}.#{prop.name} uses the reserved assign name #{prop.name}"

      unknown_fields =
        for {name, _config} <- fields,
            name not in names,
            do: "fields lists #{name}, which is not in the catalog"

      unknown_forms =
        for {name, _prop} <- forms,
            name not in names,
            do: "forms lists #{name}, which is not in the catalog"

      missing ++ reserved ++ unknown_fields ++ unknown_forms
    end
  end
end
