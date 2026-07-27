defmodule Waffle.Storage.Google.Error do
  @moduledoc """
  A failed GCS operation.

  For HTTP-level failures, `status` is the response status, `reason` is the
  message from the GCS error body (falling back to the decoded body, then the
  raw body), and `raw` holds the `Waffle.Storage.Google.Client.Response`.

  For connection-level failures (nothing came back), `status` and `raw` are
  `nil` and `reason` carries the transport's error term.
  """

  alias Waffle.Storage.Google.Client.Response

  defexception [:status, :reason, :raw]

  @type t :: %__MODULE__{
          status: non_neg_integer() | nil,
          reason: term(),
          raw: Response.t() | nil
        }

  @doc """
  Builds an `Error` from a non-2xx response.
  """
  @spec from_response(Response.t(), module()) :: t()
  def from_response(%Response{status: status, body: body} = response, json_codec) do
    reason =
      case json_codec.decode(body) do
        {:ok, %{"error" => %{"message" => message}}} -> message
        {:ok, decoded} -> decoded
        {:error, _} -> body
      end

    %__MODULE__{status: status, reason: reason, raw: response}
  end

  @impl true
  def message(%__MODULE__{status: nil, reason: reason}) do
    "GCS request failed to complete: #{inspect(reason)}"
  end

  def message(%__MODULE__{status: status, reason: reason}) do
    "GCS request failed with status #{status}: #{inspect(reason)}"
  end
end
