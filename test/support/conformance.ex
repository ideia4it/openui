defmodule OpenUI.Conformance do
  @moduledoc false

  @root Path.expand("../fixtures/openui-spec", __DIR__)

  def root, do: @root

  def program_case_ids do
    @root
    |> Path.join("*/*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, @root))
    |> Enum.sort()
  end

  def files(id) do
    dir = Path.join(@root, id)

    dir
    |> File.ls!()
    |> Map.new(&{&1, File.read!(Path.join(dir, &1))})
  end
end
