defmodule Mix.Tasks.Openui.Gen.Spec do
  @shortdoc "Writes the LibrarySpec (library.json) of an OpenUI library"

  @moduledoc """
  Writes the LibrarySpec of a library module, the `library.json` other
  clients (a React app, a mobile app) build their library from.

      mix openui.gen.spec MyApp.Library --out assets/library.json

  With `--check` nothing is written. The task fails when the new spec would
  break programs stored with the old one (a prop moved or removed, a new
  required prop without a default), when the file is out of date, or when it
  is not a valid LibrarySpec. Run it in CI so the file never drifts from the
  module.
  """

  use Mix.Task

  alias OpenUI.Library
  alias OpenUI.Library.Compat

  @impl Mix.Task
  def run(args) do
    {opts, positional} = OptionParser.parse!(args, strict: [out: :string, check: :boolean])

    with [module_name] <- positional,
         {:ok, out} <- Keyword.fetch(opts, :out) do
      spec = module_name |> load_library() |> Library.to_spec()
      generated = OpenUI.JSON.encode!(spec, pretty: true)
      if opts[:check], do: check(out, spec, generated), else: write(out, generated)
    else
      _usage -> Mix.raise("Usage: mix openui.gen.spec MyApp.Library --out library.json [--check]")
    end
  end

  defp load_library(module_name) do
    module = Module.concat([module_name])

    unless Code.ensure_loaded?(module) do
      Mix.Task.run("compile")
    end

    if Code.ensure_loaded?(module) and function_exported?(module, :__openui_library__, 0),
      do: module,
      else: Mix.raise("#{module_name} is not a module that uses OpenUI.Library")
  end

  defp write(out, generated) do
    File.mkdir_p!(Path.dirname(out))
    File.write!(out, generated)
    Mix.shell().info("Wrote #{out}")
    :ok
  end

  defp check(out, spec, generated) do
    if File.exists?(out),
      do: check_committed(out, File.read!(out), spec, generated),
      else: up_to_date(out, "", generated)
  end

  defp check_committed(out, current, spec, generated) do
    with {:ok, committed} <- Library.from_spec(current),
         [] <- Compat.check(Library.to_spec(committed), spec) do
      up_to_date(out, current, generated)
    else
      {:error, problems} ->
        Mix.raise("#{out} is not a valid LibrarySpec:\n" <> Enum.join(problems, "\n"))

      problems ->
        Mix.raise("#{out} would break stored programs:\n" <> Enum.join(problems, "\n"))
    end
  end

  defp up_to_date(out, current, generated) do
    if current == generated,
      do: :ok,
      else: Mix.raise("#{out} is out of date; run mix openui.gen.spec without --check")
  end
end
