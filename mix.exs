defmodule OpenUI.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ideia4it/openui"

  def project do
    [
      app: :openui,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "OpenUI",
      description:
        "An Elixir implementation of the OpenUI Lang 1.0 specification, with a Phoenix LiveView renderer.",
      source_url: @source_url,
      package: package(),
      docs: docs(),
      dialyzer: [plt_add_apps: [:mix], plt_local_path: "priv/plts", plt_core_path: "priv/plts"]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test"
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "OpenUI spec" => "https://github.com/thesysdev/openui/tree/main/spec"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE NOTICE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.1", optional: true},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end
