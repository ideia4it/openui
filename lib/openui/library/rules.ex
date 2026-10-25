defmodule OpenUI.Library.Rules do
  @moduledoc """
  The definition-time rules of a library (prompt.md, section 3.1).
  """

  alias OpenUI.Library

  @reserved ["Query", "Mutation" | OpenUI.Builtins.names()]

  @doc "Names no component, function or action may use."
  @spec reserved_names() :: [String.t()]
  def reserved_names, do: @reserved

  @doc "Returns every rule the library breaks, as messages. An empty list means it conforms."
  @spec check(Library.t()) :: [String.t()]
  def check(%Library{} = library) do
    named =
      Enum.map(library.components, &{"component", &1.name, &1.props}) ++
        Enum.map(library.functions, &{"function", &1.name, &1.params}) ++
        Enum.map(library.actions, &{"action", &1.name, &1.params})

    component_names = Enum.map(library.components, & &1.name)

    Enum.flat_map(named, &name_problems/1) ++
      duplicate_problems(named) ++
      Enum.flat_map(named, &order_problems/1) ++
      root_problems(library.root, component_names) ++
      Enum.flat_map(library.groups, &group_problems(&1, component_names))
  end

  defp name_problems({kind, name, _props}) do
    cond do
      name in @reserved ->
        ["#{kind} #{name} uses a reserved name"]

      not Regex.match?(~r/^[A-Z][A-Za-z0-9_]*$/, name) ->
        ["#{kind} #{name} must start with an uppercase letter"]

      true ->
        []
    end
  end

  defp duplicate_problems(named) do
    named
    |> Enum.frequencies_by(&elem(&1, 1))
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> "#{name} is defined more than once" end)
  end

  # A required prop with a default counts as optional, so it may be appended
  # to an existing component without breaking stored programs.
  defp order_problems({_kind, owner, props}) do
    {problems, _seen_optional?} =
      Enum.reduce(props, {[], false}, fn prop, {problems, seen_optional?} ->
        optional? = not prop.required? or prop.default != :none

        cond do
          optional? ->
            {problems, true}

          seen_optional? ->
            {["#{owner}: required prop #{prop.name} comes after an optional prop" | problems],
             true}

          true ->
            {problems, false}
        end
      end)

    Enum.reverse(problems)
  end

  defp root_problems(nil, _component_names), do: []

  defp root_problems(root, component_names) do
    if root in component_names, do: [], else: ["root #{root} is not a component"]
  end

  defp group_problems(group, component_names) do
    group.components
    |> Enum.reject(&(&1 in component_names))
    |> Enum.map(&"group #{group.name} lists #{&1}, which is not a component")
  end
end
