defmodule ChainBench.MixProject do
  use Mix.Project

  def project do
    [
      app: :chain_bench,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ChainBench.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, "~> 1.4"},
      {:benchee_html, "~> 1.0"}, # For generating HTML reports
      {:jason, "~> 1.4"}, # Benchee.Formatters.JSON uses Jason
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
