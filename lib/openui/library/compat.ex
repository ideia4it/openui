defmodule OpenUI.Library.Compat do
  @moduledoc """
  Checks that a new version of a LibrarySpec keeps stored programs readable
  (prompt.md, section 3.2): props of components, functions and actions are
  only added at the end, never moved or removed, and a new required prop
  carries a default.
  """

  alias OpenUI.JSON.Object

  @doc "Returns every rule the new spec breaks against the old one."
  @spec check(Object.t(), Object.t()) :: [String.t()]
  def check(%Object{} = old_spec, %Object{} = new_spec) do
    old = owners(old_spec)
    new = owners(new_spec)

    Enum.flat_map(old, fn {{_kind, name} = owner, old_props} ->
      case List.keyfind(new, owner, 0) do
        {^owner, new_props} -> compare(name, old_props, new_props)
        nil -> []
      end
    end)
  end

  # Components and the params of functions and actions, each as
  # {{kind, name}, [{prop, required_without_default?}]} in positional order.
  # $defs also holds action shapes, which are not components.
  defp owners(spec) do
    schema = Object.get(spec, "schema") || %Object{}
    components = schema |> Object.get("properties") |> pairs() |> Enum.map(&elem(&1, 0))

    component_owners =
      for {name, definition} <- pairs(Object.get(schema, "$defs")), name in components do
        {{:component, name}, props(definition)}
      end

    call_owners =
      for {kind, section} <- [function: "functions", action: "actions"],
          {name, definition} <- pairs(Object.get(schema, section)) do
        {{kind, name}, props(Object.get(definition, "params") || %Object{})}
      end

    component_owners ++ call_owners
  end

  defp pairs(%Object{pairs: pairs}), do: pairs
  defp pairs(_missing), do: []

  defp props(object) do
    required = Object.get(object, "required") || []

    for {prop, schema} <- pairs(Object.get(object, "properties")) do
      {prop, prop in required and Object.get(schema, "default", :none) == :none}
    end
  end

  defp compare(owner, old_props, new_props) do
    old_names = Enum.map(old_props, &elem(&1, 0))
    new_names = Enum.map(new_props, &elem(&1, 0))

    removed =
      for name <- old_names, name not in new_names, do: "#{owner}: prop #{name} was removed"

    moved =
      for {name, old_index} <- Enum.with_index(old_names, 1),
          new_index = Enum.find_index(new_names, &(&1 == name)),
          new_index != nil and new_index + 1 != old_index do
        "#{owner}: prop #{name} moved from position #{old_index} to #{new_index + 1}"
      end

    added_required =
      for {name, true} <- new_props,
          name not in old_names,
          do: "#{owner}: new required prop #{name} needs a default"

    removed ++ moved ++ added_required
  end
end
