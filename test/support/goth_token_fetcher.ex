# Only compiled on goth >= 1.3: Goth.fetch!/1 doesn't exist below that, and
# the bare reference would trip --warnings-as-errors on the old-goth blend
# runs (where integration — the only caller — is excluded anyway).
# Delete this gate when the goth requirement moves past 1.3 (see the old-goth
# block in test/test_helper.exs for the full removal checklist).
if Version.match?(to_string(Application.spec(:goth, :vsn)), ">= 1.3.0") do
  defmodule Waffle.GothTokenFetcher do
    @moduledoc """
    An example of fetching token for Goth >= 1.3.0
    """
    @behaviour Waffle.Storage.Google.Token.Fetcher

    @impl true
    def get_token(_scope) do
      Goth.fetch!(Waffle.Goth).token
    end
  end
end
