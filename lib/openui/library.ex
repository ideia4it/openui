defmodule OpenUI.Library do
  @moduledoc """
  A component library: the components, custom functions, custom actions and
  groups a program may use (prompt.md, section 2).

  A library comes from a LibrarySpec document with `from_spec/2`, or from a
  module defined with `use OpenUI.Library`. Either way `to_spec/1` gives the
  LibrarySpec back, ready to share with other clients.
  """

  alias OpenUI.JSON
  alias OpenUI.JSON.Object
  alias OpenUI.Library.{Callable, Component, Group, Prop, Rules}

  @derive {Inspect, only: [:id, :version, :root]}
  defstruct [
    :id,
    :version,
    :root,
    components: [],
    functions: [],
    actions: [],
    groups: [],
    spec: nil
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          version: String.t() | nil,
          root: String.t() | nil,
          components: [Component.t()],
          functions: [Callable.t()],
          actions: [Callable.t()],
          groups: [Group.t()],
          spec: Object.t() | nil
        }

  @builtin_action_refs ~w(ActionExpression OpenUrl ToAssistant)

  @doc """
  Defines a library in a module:

      defmodule MyApp.Library do
        use OpenUI.Library, id: "myapp", version: "1.0.0", root: "Stack"

        component "Stack",
          description: "Lays out children in a column",
          props: [children: [type: {:array, :component}, required: true]]

        function "Percent",
          description: "Part over total as a percentage",
          params: [part: [type: :number, required: true], total: [type: :number, required: true]],
          returns: :string,
          impl: &MyApp.Formulas.percent/1

        action "CopyToClipboard", description: "Copies text", params: [text: [type: :string, required: true]]

        group "Layout", ["Stack"], notes: ["Wrap every page in a Stack."]
      end

  See `OpenUI.Library.DSL` for the macros and the prop types.
  """
  defmacro __using__(opts) do
    quote do
      use OpenUI.Library.DSL, unquote(opts)
    end
  end

  @doc """
  Reads a LibrarySpec, given as JSON text or as a decoded `OpenUI.JSON.Object`.

  Custom functions have no implementation in the spec; pass them as
  `functions: %{"Name" => fun}`, each `fun` taking one map keyed by the param
  names.
  """
  @spec from_spec(binary() | Object.t(), keyword()) :: {:ok, t()} | {:error, [String.t()]}
  def from_spec(spec, opts \\ [])

  def from_spec(json, opts) when is_binary(json) do
    case JSON.decode(json) do
      {:ok, %Object{} = spec} -> from_spec(spec, opts)
      {:ok, _other} -> {:error, ["a LibrarySpec must be a JSON object"]}
      {:error, reason} -> {:error, ["invalid JSON: #{inspect(reason)}"]}
    end
  end

  def from_spec(%Object{} = spec, opts) do
    library = read_spec(spec, Keyword.get(opts, :functions, %{}))

    case Rules.check(library) do
      [] -> {:ok, library}
      problems -> {:error, problems}
    end
  end

  @doc "Returns the LibrarySpec of a library or of a module that uses `OpenUI.Library`."
  @spec to_spec(t() | module()) :: Object.t()
  def to_spec(library), do: resolve(library).spec

  @doc "Returns the library itself, or the library a module defines with `use OpenUI.Library`."
  @spec resolve(t() | module()) :: t()
  def resolve(%__MODULE__{} = library), do: library
  def resolve(module) when is_atom(module), do: module.__openui_library__()

  @doc "Finds a component by name."
  @spec component(t(), String.t()) :: Component.t() | nil
  def component(%__MODULE__{components: components}, name),
    do: Enum.find(components, &(&1.name == name))

  @doc "Finds a custom function by name."
  @spec function(t(), String.t()) :: Callable.t() | nil
  def function(%__MODULE__{functions: functions}, name),
    do: Enum.find(functions, &(&1.name == name))

  @doc "Finds a custom action by name."
  @spec action(t(), String.t()) :: Callable.t() | nil
  def action(%__MODULE__{actions: actions}, name), do: Enum.find(actions, &(&1.name == name))

  defp read_spec(spec, implementations) do
    schema = field(spec, "schema")
    defs = field(schema, "$defs")
    signatures = field(spec, "components")
    component_names = Enum.uniq(keys(signatures) ++ keys(field(schema, "properties")))
    action_refs = keys(field(schema, "actions")) ++ @builtin_action_refs
    classify = &kind(&1, component_names, action_refs)

    %__MODULE__{
      id: Object.get(spec, "id"),
      version: Object.get(spec, "version"),
      root: Object.get(spec, "root"),
      components: Enum.map(component_names, &read_component(&1, defs, signatures, classify)),
      functions:
        read_callables(
          field(schema, "functions"),
          field(spec, "functions"),
          implementations,
          classify
        ),
      actions: read_callables(field(schema, "actions"), field(spec, "actions"), %{}, classify),
      groups: Enum.map(Object.get(spec, "componentGroups", []), &read_group/1),
      spec: spec
    }
  end

  defp read_component(name, defs, signatures, classify) do
    prompt = field(signatures, name)
    signature = Object.get(prompt, "signature", "")

    %Component{
      name: name,
      description: Object.get(prompt, "description", ""),
      signature: signature,
      props: read_props(field(defs, name), signature, classify)
    }
  end

  defp read_callables(schemas, prompts, implementations, classify) do
    for name <- keys(schemas) do
      schema = field(schemas, name)
      prompt = field(prompts, name)
      returns = Object.get(schema, "returns")
      signature = Object.get(prompt, "signature", "")

      %Callable{
        name: name,
        description: Object.get(schema, "description") || Object.get(prompt, "description", ""),
        signature: signature,
        params: read_props(field(schema, "params"), signature, classify),
        returns: returns && JSON.to_plain(returns),
        impl: Map.get(implementations, name)
      }
    end
  end

  defp read_props(object_schema, signature, classify) do
    required = Object.get(object_schema, "required", [])
    bindable = bindable_names(signature)

    for {name, prop_schema} <- field(object_schema, "properties").pairs do
      plain = JSON.to_plain(prop_schema)

      %Prop{
        name: name,
        schema: plain,
        required?: name in required,
        default: Map.get(plain, "default", :none),
        bindable?: name in bindable,
        kind: classify.(plain)
      }
    end
  end

  defp read_group(group) do
    %Group{
      name: Object.get(group, "name"),
      components: Object.get(group, "components", []),
      notes: Object.get(group, "notes", [])
    }
  end

  defp bindable_names(signature) do
    ~r/(\w+)\??: \$binding</
    |> Regex.scan(signature, capture: :all_but_first)
    |> List.flatten()
  end

  defp kind(schema, component_names, action_refs) do
    cond do
      refs_only?(schema, action_refs) -> :action
      refs_only?(Map.get(schema, "items", schema), component_names) -> :components
      true -> :value
    end
  end

  defp refs_only?(%{"$ref" => ref}, names), do: ref_name(ref) in names

  defp refs_only?(%{"anyOf" => [_ | _] = options}, names),
    do: Enum.all?(options, &refs_only?(&1, names))

  defp refs_only?(_schema, _names), do: false

  defp ref_name("#/$defs/" <> name), do: name
  defp ref_name(_ref), do: nil

  # A spec may leave any section out; read a missing one as an empty object.
  defp field(%Object{} = object, key), do: Object.get(object, key) || %Object{}

  defp keys(%Object{} = object), do: Object.keys(object)
end
