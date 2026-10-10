defmodule Waffle.Storage.Google.Transport do
  @moduledoc """
  Behaviour for executing `Waffle.Storage.Google.Client.Request`s over HTTP.

  The default implementation is `Waffle.Storage.Google.Transport.Req`.
  Configure a different one with:

  ```elixir
  config :waffle_gcs, transport: MyApp.GCSTransport
  ```

  A transport must return the response as-is — no JSON decoding, no error
  mapping beyond its own connection-level failures. Result interpretation
  belongs to `Waffle.Storage.Google.Client`.
  """

  alias Waffle.Storage.Google.Client.{Request, Response}

  @callback execute(Request.t(), opts :: keyword()) :: {:ok, Response.t()} | {:error, term()}
end
