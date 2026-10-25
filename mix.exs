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
      dialyzer: [plt_add_apps: [:mix], plt_local_path: "priv/plts", plt_core_path: "priv/plts"],
      test_coverage: test_coverage()
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
        "test --cover"
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
      files: ~w(lib mix.exs .formatter.exs README.md CHANGELOG.md LICENSE NOTICE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/defining-a-catalog.md",
        "guides/liveview.md",
        "guides/req-llm.md",
        "guides/jido-ai.md",
        "guides/react-app.md",
        "guides/errors-and-safeguards.md",
        "guides/stored-programs.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [Guides: ~r{guides/}],
      groups_for_modules: [
        Catalog: [
          OpenUI.Library,
          OpenUI.Library.DSL,
          OpenUI.Library.Compat,
          ~r/OpenUI\.Library\./
        ],
        Language: [OpenUI.Parser, OpenUI.Stream, OpenUI.Edit, OpenUI.Serializer, OpenUI.Canonical],
        Runtime: [OpenUI.Runtime, ~r/OpenUI\.Runtime\./],
        LiveView: [OpenUI.LiveView, OpenUI.LiveView.Components],
        Prompt: [OpenUI.Prompt, OpenUI.Message],
        Data: [
          OpenUI.Program,
          OpenUI.Program.Query,
          OpenUI.Program.Mutation,
          OpenUI.Statement,
          OpenUI.Element,
          OpenUI.Unknown,
          OpenUI.ActionPlan,
          OpenUI.Binding,
          OpenUI.Error,
          OpenUI.Event,
          OpenUI.JSON,
          OpenUI.JSON.Object,
          OpenUI.Builtins
        ]
      ]
    ]
  end

  # Every line of lib/ runs in a test except __components__/0, which
  # `use Phoenix.LiveComponent` generates in OpenUI.LiveView.Program and Phoenix
  # only calls at compile time; cover ignores whole modules, not single lines.
  defp test_coverage do
    [
      summary: [threshold: 99.95],
      ignore_modules: [OpenUI.Conformance, OpenUI.LiveCase, ~r/OpenUI\.Test\./]
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
