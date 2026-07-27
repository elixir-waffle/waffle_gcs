defmodule Waffle.Storage.Google.Client.Response do
  @moduledoc """
  The transport-level result of executing a `Waffle.Storage.Google.Client.Request`:
  status, headers, and the raw (undecoded) body.

  Carried on `Waffle.Storage.Google.Object` and `Waffle.Storage.Google.Error`
  under the `:raw` key.
  """

  defstruct [:status, :headers, :body]

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          headers: [{String.t(), String.t()}],
          body: binary()
        }
end
