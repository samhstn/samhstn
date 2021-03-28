defmodule Samhstn.MixProject do
  use Mix.Project

  @version "1.0.0"
  @elixir_version "1.10"

  def project do
    [
      app: :samhstn,
      version: @version,
      elixir: "~> #{@elixir_version}",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      compilers: [:phoenix] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Samhstn.Application, []},
      extra_applications: [:logger, :runtime_tools, :iex]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:httpoison, "~> 1.7"},
      {:phoenix, "~> 1.5.4"},
      {:phoenix_html, "~> 2.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:sobelow, "~> 0.10.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:poison, "~> 3.0"},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, github: "ex-aws/ex_aws_s3", ref: "master"},
      {:ex_aws_sts, "~> 2.0"},
      {:sweet_xml, "~> 0.6"},
      {:configparser_ex, "~> 4.0"}
    ]
  end
end
