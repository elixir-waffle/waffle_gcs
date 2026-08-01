defmodule Waffle.Storage.Google.Transport.Req do
  @moduledoc """
  The default `Waffle.Storage.Google.Transport`: executes requests with
  [Req](https://hex.pm/packages/req).

  Extra Req options (connection pool, proxy, `:plug` for tests, ...) merge
  into every request via:

  ```elixir
  config :waffle_gcs, Waffle.Storage.Google.Transport.Req, req_options: [...]
  ```
  """

  @behaviour Waffle.Storage.Google.Transport

  alias Waffle.Storage.Google.Client.{Request, Response}

  @impl true
  def execute(%Request{} = request, _opts) do
    [
      method: request.method,
      url: request.url,
      params: request.query,
      headers: request.headers,
      retry: false,
      decode_body: false
    ]
    |> put_body(request.body)
    |> Keyword.merge(req_options())
    |> Req.request()
    |> case do
      {:ok, %Req.Response{} = response} ->
        {:ok,
         %Response{
           status: response.status,
           headers: flatten_headers(response.headers),
           body: response.body,
           raw: response
         }}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp put_body(options, nil), do: options
  defp put_body(options, body), do: Keyword.put(options, :body, body)

  defp flatten_headers(headers) when is_map(headers) do
    for {name, values} <- headers, value <- List.wrap(values), do: {name, value}
  end

  defp flatten_headers(headers) when is_list(headers), do: headers

  defp req_options do
    :waffle_gcs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:req_options, [])
  end
end
