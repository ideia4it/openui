defmodule OpenUI.Library.SpecShape do
  @moduledoc false
  # The JSON type of every section of a LibrarySpec that OpenUI.Library reads
  # (prompt.md, section 2), checked before reading so that a library.json from
  # disk or the network gets problems back instead of an exception. A section
  # that is missing or null reads as empty.

  alias OpenUI.JSON.Object

  @any_object {:object, []}
  @prompt {:object, [{"signature", :string}, {"description", :string}]}

  @object_schema {:object,
                  [{"properties", {:object_of, @any_object}}, {"required", {:list_of, :string}}]}

  @call_schema {:object, [{"description", :string}, {"params", @object_schema}]}

  @group {:object,
          [
            {"name", :string},
            {"components", {:list_of, :string}},
            {"notes", {:list_of, :string}}
          ]}

  @spec_shape {:object,
               [
                 {"id", :string},
                 {"version", :string},
                 {"root", :string},
                 {"components", {:object_of, @prompt}},
                 {"componentGroups", {:list_of, @group}},
                 {"functions", {:object_of, @prompt}},
                 {"actions", {:object_of, @prompt}},
                 {"schema",
                  {:object,
                   [
                     {"properties", @any_object},
                     {"$defs", {:object_of, @object_schema}},
                     {"functions", {:object_of, @call_schema}},
                     {"actions", {:object_of, @call_schema}}
                   ]}}
               ]}

  @doc false
  def problems(%Object{} = spec), do: check(spec, @spec_shape, "")

  defp check(%Object{} = object, {:object, fields}, path) do
    Enum.flat_map(fields, fn {key, shape} ->
      section(Object.get(object, key), shape, join(path, key))
    end)
  end

  defp check(%Object{pairs: pairs}, {:object_of, shape}, path),
    do: Enum.flat_map(pairs, fn {key, value} -> section(value, shape, join(path, key)) end)

  defp check(list, {:list_of, shape}, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} -> check(item, shape, "#{path}[#{index}]") end)
  end

  defp check(text, :string, _path) when is_binary(text), do: []
  defp check(_value, shape, path), do: ["#{path} must be #{expected(shape)}"]

  defp section(nil, _shape, _path), do: []
  defp section(value, shape, path), do: check(value, shape, path)

  defp join("", key), do: key
  defp join(path, key), do: path <> "." <> key

  defp expected(:string), do: "a string"
  defp expected({:list_of, _shape}), do: "a list"
  defp expected(_object_shape), do: "an object"
end
