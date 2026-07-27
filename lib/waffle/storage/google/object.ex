defmodule Waffle.Storage.Google.Object do
  @moduledoc """
  A stored GCS object, decoded from the JSON API's object resource.

  `raw` holds the underlying `Waffle.Storage.Google.Client.Response` (with the
  undecoded body) when the object came from a dedicated request, and `nil` for
  objects embedded in a list response.
  """

  alias Waffle.Storage.Google.Client.Response

  defstruct [:name, :bucket, :content_type, :size, :generation, :acl, :raw]

  @type t :: %__MODULE__{
          name: String.t(),
          bucket: String.t() | nil,
          content_type: String.t() | nil,
          size: non_neg_integer() | nil,
          generation: String.t() | nil,
          acl: [map()] | nil,
          raw: Response.t() | nil
        }

  @doc """
  Builds an `Object` from a decoded object resource.
  """
  @spec from_map(map(), Response.t() | nil) :: t()
  def from_map(map, raw \\ nil) when is_map(map) do
    %__MODULE__{
      name: map["name"],
      bucket: map["bucket"],
      content_type: map["contentType"],
      size: parse_size(map["size"]),
      generation: map["generation"],
      acl: map["acl"],
      raw: raw
    }
  end

  defp parse_size(nil), do: nil
  defp parse_size(size) when is_integer(size), do: size
  defp parse_size(size) when is_binary(size), do: String.to_integer(size)
end
