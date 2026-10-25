Mix.install([{:openui, path: Path.expand("../../..", __DIR__)}])

# Same implementation as FUNCTIONS in contract.test.ts.
percent = fn %{"part" => part, "total" => total} -> "#{round(part / total * 100)}%" end

{:ok, library} =
  Path.expand("../library.json", __DIR__)
  |> File.read!()
  |> OpenUI.Library.from_spec(functions: %{"Percent" => percent})

Path.expand("programs/*.oui", __DIR__)
|> Path.wildcard()
|> Map.new(fn path ->
  program = path |> File.read!() |> OpenUI.Parser.parse(library)
  {Path.basename(path), OpenUI.Canonical.result(program, library)}
end)
|> OpenUI.JSON.encode!(pretty: true)
|> then(&File.write!(Path.expand("elixir.json", __DIR__), &1))
