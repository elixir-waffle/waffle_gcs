defmodule GCSTest.StubFetcher do
  @moduledoc "Token fetcher for offline tests."
  @behaviour Waffle.Storage.Google.Token.Fetcher

  @impl true
  def get_token(_scope), do: "stub-token"
end

defmodule GCSTest.StubTransport do
  @moduledoc """
  Transport for offline tests: sends every request to the test process as
  `{:request, request}` and answers with `opts[:respond].(request)`, or a
  canned 200 object when no `:respond` is given.
  """
  @behaviour Waffle.Storage.Google.Transport

  alias Waffle.Storage.Google.Client.Response

  @impl true
  def execute(request, opts) do
    send(self(), {:request, request})

    case Keyword.get(opts, :respond) do
      nil -> {:ok, %Response{status: 200, headers: [], body: ~s({"name": "captured"})}}
      respond -> respond.(request)
    end
  end
end

defmodule GCSTest.Env do
  @moduledoc "Restores an application env key to its pre-test value."

  def restore(app, key, nil), do: Application.delete_env(app, key)
  def restore(app, key, value), do: Application.put_env(app, key, value)
end
