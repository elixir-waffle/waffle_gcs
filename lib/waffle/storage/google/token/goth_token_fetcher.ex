if Version.match?(to_string(Application.spec(:goth, :vsn)), "< 1.3.0") do
  defmodule Waffle.Storage.Google.Token.GothTokenFetcher do
    @moduledoc """
    A token fetcher that uses Goth 1.1 to fetch a token for a given scope.
    This module would raise an runtime exception if Goth 1.3 or newer is available.
    """
    @behaviour Waffle.Storage.Google.Token.Fetcher

    @impl true
    def get_token(scope) when is_binary(scope) do
      {:ok, token} = Goth.Token.for_scope(scope)
      token.token
    end
  end
end
