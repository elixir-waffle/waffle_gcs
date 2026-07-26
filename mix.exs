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

  # Reviewed and accepted; revisit alongside #39. Consumed by both audit tools
  # (see the `audit` alias).
  defp ignored_advisories do
    ~w(
      GHSA-mc85-72gr-vm9f GHSA-9m9w-gxf7-rh8m GHSA-h74c-q9j7-mpcm
      GHSA-28jh-g32x-v9v4 GHSA-q7jx-v53g-848w
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
  # `mix audit` runs the hex.audit and mix_audit dependency checks; both honor
  # ignored_advisories/0.
  defp aliases do
    [
      "test.unit": ["test --exclude integration"],
      audit: [
        "hex.audit",
        "deps.audit --ignore-advisory-ids #{Enum.join(ignored_advisories(), ",")}"
      ]
    ]
  end

  defp description do
    "Google Cloud Storage integration for Waffle file uploader library."
  end

  defp package do
    [
      # No config/: a library's config files are never evaluated by consumers.
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
      {:google_api_storage, "~> 0.34"},
      # Direct dependency for content-type inference (already transitive via
      # google_gax); google_gax's "~> 1.0" constraint governs resolution.
      {:mime, "~> 1.2 or ~> 2.0"},
      # tesla is transitive via google_gax; newer tesla is incompatible with
      # google_gax's compiled-in middleware stack. Pinned pending the client
      # rewrite (#39).
      {:tesla, "1.18.2"},
      {:blend, "~> 0.5.0", only: :dev},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end
end
