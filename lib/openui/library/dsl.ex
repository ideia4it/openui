defmodule OpenUI.Library.DSL do
  @moduledoc """
  The macros of `use OpenUI.Library`: `component/2`, `function/2`,
  `action/2` and `group/3`. See `OpenUI.Library` for an example.

  The library is built and checked when the module compiles: a catalog that
  breaks the rules of prompt.md, section 3.1, does not compile.
  """

  alias OpenUI.Library
  alias OpenUI.Library.Schema

  @doc false
  defmacro __using__(opts) do
    quote do
      import OpenUI.Library.DSL, only: [component: 2, function: 2, action: 2, group: 2, group: 3]

      for attribute <- [:openui_components, :openui_functions, :openui_actions, :openui_groups] do
        Module.register_attribute(__MODULE__, attribute, accumulate: true)
      end

      @openui_options unquote(opts)
      @before_compile OpenUI.Library.DSL
    end
  end

  @doc "Defines a component: `description:` and `props:`, a keyword list of `name: [type: ..., required: ..., default: ...]` in positional order."
  defmacro component(name, opts) do
    quote do: @openui_components({unquote(name), unquote(opts)})
  end

  @doc """
  Defines a custom function: `description:`, `params:`, `returns:` and
  `impl:`, a remote capture such as `&MyApp.Formulas.percent/1` that receives
  one map keyed by the param names.
  """
  defmacro function(name, opts) do
    unless remote_capture?(Keyword.get(opts, :impl)) do
      raise CompileError,
        description: "#{name}: impl must be a remote capture like &Mod.fun/1",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    quote do: @openui_functions({unquote(name), unquote(opts)})
  end

  @doc "Defines a custom action, delivered to the host when it runs: `description:` and `params:`."
  defmacro action(name, opts) do
    quote do: @openui_actions({unquote(name), unquote(opts)})
  end

  @doc "Groups components under a title in the prompt, with optional `notes:`."
  defmacro group(name, components, opts \\ []) do
    quote do: @openui_groups({unquote(name), unquote(components), unquote(opts)})
  end

  @doc false
  defmacro __before_compile__(env) do
    read = fn attribute -> env.module |> Module.get_attribute(attribute) |> Enum.reverse() end

    built =
      Schema.build(
        Module.get_attribute(env.module, :openui_options),
        read.(:openui_components),
        read.(:openui_functions),
        read.(:openui_actions),
        read.(:openui_groups)
      )

    with {:ok, spec, implementations} <- built,
         {:ok, library} <- Library.from_spec(spec, functions: implementations) do
      quote do
        @doc false
        def __openui_library__, do: unquote(Macro.escape(library))
      end
    else
      {:error, problems} ->
        raise CompileError, description: Enum.join(problems, "; "), file: env.file, line: env.line
    end
  end

  defp remote_capture?({:&, _, [{:/, _, [{{:., _, [_module, function]}, _, []}, arity]}]}),
    do: is_atom(function) and is_integer(arity)

  defp remote_capture?(_ast), do: false
end
