defmodule Flagex.MixProject do
  use Mix.Project

  def project do
    [
      app: :flagex,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: "Runtime configuration variables for Phoenix applications, backed by PostgreSQL.",
      source_url: "https://github.com/GabriellaDiasA/flagex",
      deps: deps(),
      aliases: aliases(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19"},
      {:jason, "~> 1.4"},

      # HTTP API
      {:plug, "~> 1.16"},

      # Optional clustering cache
      {:nebulex, "~> 2.6", optional: true},
      {:nebulex_adapters_cachex, "~> 2.1", optional: true},
      {:cachex, "~> 3.6", optional: true},

      # Dev/test
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/GabriellaDiasA/flagex"}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/GabriellaDiasA/flagex",
      extras: ["README.md", "LICENSE.md"]
    ]
  end

  defp aliases do
    [
      "test.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      test: ["ecto.create --quiet", "test"]
    ]
  end
end
