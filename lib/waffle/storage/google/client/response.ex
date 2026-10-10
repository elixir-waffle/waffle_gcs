defmodule Waffle.Storage.Google.Client.Response do
  @moduledoc """
  The normalized result of executing a `Waffle.Storage.Google.Client.Request`:
  status, headers, and the raw (undecoded) body. This is the contract between
  transports and the client — `Waffle.Storage.Google.Client` reads results
  through this shape regardless of which HTTP library executed the request.

  `raw` is the transport's native response (e.g. a `Req.Response`), set by the
  transport for escape-hatch access; its shape depends on the configured
  transport.

  Carried on `Waffle.Storage.Google.Object` and `Waffle.Storage.Google.Error`
  under the `:response` key.
  """

  defstruct [:status, :headers, :body, :raw]

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          headers: [{String.t(), String.t()}],
          body: binary(),
          raw: term()
        }
end
