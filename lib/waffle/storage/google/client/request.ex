defmodule Waffle.Storage.Google.Client.Request do
  @moduledoc """
  A GCS API request as plain data, built by `Waffle.Storage.Google.Client`
  and executed by a `Waffle.Storage.Google.Transport`.
  """

  defstruct method: :get, url: nil, query: [], headers: [], body: nil

  @type t :: %__MODULE__{
          method: :get | :post | :put | :delete,
          url: String.t(),
          query: [{atom() | String.t(), String.t()}],
          headers: [{String.t(), String.t()}],
          body: iodata() | nil
        }
end
