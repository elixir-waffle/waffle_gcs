# Lets `BLEND=<name> mix ...` run against a blend's lockfile (see blend.exs).
if File.exists?("blend/premix.exs") do
  Code.compile_file("blend/premix.exs")
end

defmodule Waffle.Storage.Google.CloudStorage.MixProject do
  use Mix.Project

  def project do
    [
      app: :waffle_gcs,
      name: "Waffle GCS",
      description: description(),
      version: "0.2.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package(),
      source_url: "https://github.com/elixir-waffle/waffle_gcs",
      homepage_url: "https://github.com/elixir-waffle/waffle_gcs",
      hex: [ignore_advisories: ignored_advisories()]
    ]
    |> Keyword.merge(maybe_lockfile_option())
  end

  # hackney, transitive via waffle ~> 1.1; fixed only in hackney 4.x, which
  # waffle's ~> 1.9 constraint can't reach. Reviewed and accepted — hackney
  # is only used for waffle's own remote-file downloads, not by this adapter.
  defp ignored_advisories do
    ~w(
      GHSA-gp9c-pm5m-5cxr GHSA-j9wq-vxxc-94wf GHSA-mp55-p8c9-rfw2
      GHSA-pj7v-xfvx-wmjq
    )
  end

  # Set by blend/premix.exs when BLEND is set; MIX_DEPS_PATH and
  # MIX_BUILD_ROOT are consumed by Mix itself.
  defp maybe_lockfile_option do
    case System.get_env("MIX_LOCKFILE") do
      nil -> []
      "" -> []
      lockfile -> [lockfile: lockfile]
    end
  end

  # Run the test.* aliases in the :test environment.
  def cli do
    [preferred_envs: ["test.unit": :test]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # `mix test.unit` runs only the fast, offline unit tests (no GCS creds needed).
  # `mix audit` checks retirements and advisories, honoring ignored_advisories/0.
  defp aliases do
    [
      "test.unit": ["test --exclude integration"],
      audit: ["hex.audit"]
    ]
  end

  defp description do
    "Google Cloud Storage integration for Waffle file uploader library."
  end

  defp package do
    [
      files: ~w(lib LICENSE mix.exs README.md CHANGELOG.md UPGRADING.md),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/elixir-waffle/waffle_gcs",
        "Changelog" => "https://github.com/elixir-waffle/waffle_gcs/blob/main/CHANGELOG.md",
        "Upgrading" => "https://github.com/elixir-waffle/waffle_gcs/blob/main/UPGRADING.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "UPGRADING.md"],
      # Mix.Config is @moduledoc false, so autolinking it warns.
      skip_code_autolink_to: ["Mix.Config"]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:waffle, "~> 1.1"},
      {:goth, "~> 1.1"},
      # 0.6.1 is the first release without GHSA-655f-mp8p-96gv.
      {:req, "~> 0.6.1"},
      # Direct dependency for content-type inference; the floor is req's.
      {:mime, "~> 2.0.6 or ~> 2.1"},
      # Default :json_codec for the GCS client (config :waffle_gcs, :json_codec).
      {:jason, "~> 1.2"},
      {:blend, "~> 0.5.0", only: :dev},
      {:plug, "~> 1.15", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end
end
