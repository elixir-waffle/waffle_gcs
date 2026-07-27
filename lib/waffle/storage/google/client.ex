defmodule Waffle.Storage.Google.Client do
  @moduledoc """
  Minimal GCS JSON API client backing the Waffle adapter: the four operations
  the adapter needs, built as data and executed by the configured
  `Waffle.Storage.Google.Transport`.

  Results are library-owned types: `Waffle.Storage.Google.Object` on success
  and `Waffle.Storage.Google.Error` on failure, both carrying the raw
  transport response under `:raw`.

  Configuration (all optional):

  ```elixir
  config :waffle_gcs,
    transport: Waffle.Storage.Google.Transport.Req,
    json_codec: Jason,
    base_url: "https://storage.googleapis.com"
  ```

  Every option can also be passed per call (`:transport`, `:json_codec`,
  `:scope`).
  """

  alias Waffle.Storage.Google.{Error, Object, Util}
  alias Waffle.Storage.Google.Client.{Request, Response}

  @base_url "https://storage.googleapis.com"
  @full_control_scope "https://www.googleapis.com/auth/devstorage.full_control"

  @type data :: {:file, Path.t()} | {:binary, binary()}
  @type object_result :: {:ok, Object.t()} | {:error, Error.t()}

  @doc """
  Uploads an object in a single `multipart/related` request.

  `metadata` is the object resource sent as the JSON part (`:name` is set from
  `name`); entries like `:contentType` and `:acl` go here. Options:

    * `:query` — extra query parameters (e.g. `predefinedAcl: "publicRead"`)
    * `:metadata` — the object resource map
  """
  @spec insert(String.t(), String.t(), data(), keyword()) :: object_result()
  def insert(bucket, name, data, opts \\ []) do
    metadata =
      opts
      |> Keyword.get(:metadata, %{})
      |> Map.put(:name, name)

    bucket
    |> insert_request(metadata, read_data(data), Keyword.get(opts, :query, []), opts)
    |> execute(opts)
    |> map_object(opts)
  end

  @doc """
  Fetches an object's metadata. Pass `query: [projection: "full"]` to include
  ACLs.
  """
  @spec get(String.t(), String.t(), keyword()) :: object_result()
  def get(bucket, name, opts \\ []) do
    bucket
    |> get_request(name, Keyword.get(opts, :query, []))
    |> execute(opts)
    |> map_object(opts)
  end

  @doc """
  Deletes an object.
  """
  @spec delete(String.t(), String.t(), keyword()) :: :ok | {:error, Error.t()}
  def delete(bucket, name, opts \\ []) do
    bucket
    |> delete_request(name)
    |> execute(opts)
    |> case do
      {:ok, %Response{status: status}} when status in 200..299 -> :ok
      other -> {:error, to_error(other, opts)}
    end
  end

  @doc """
  Lists objects in a bucket. Supports `query: [prefix: ..., pageToken: ...]`.

  Returns `{:ok, %{items: [Object.t()], next_page_token: String.t() | nil}}`;
  listed objects carry `raw: nil`.
  """
  @spec list(String.t(), keyword()) ::
          {:ok, %{items: [Object.t()], next_page_token: String.t() | nil}} | {:error, Error.t()}
  def list(bucket, opts \\ []) do
    bucket
    |> list_request(Keyword.get(opts, :query, []))
    |> execute(opts)
    |> case do
      {:ok, %Response{status: status, body: body}} when status in 200..299 ->
        decoded = json_codec(opts).decode!(body)

        {:ok,
         %{
           items: decoded |> Map.get("items", []) |> Enum.map(&Object.from_map/1),
           next_page_token: decoded["nextPageToken"]
         }}

      other ->
        {:error, to_error(other, opts)}
    end
  end

  @doc """
  Builds the `multipart/related` insert request.

  The multipart framing is entirely library-controlled: a random boundary and
  constant part headers, except the media part's `Content-Type`, which mirrors
  the metadata's `:contentType` (as `google_gax` did) and is validated to be a
  single printable-ASCII line.
  """
  @spec insert_request(String.t(), map(), iodata(), keyword(), keyword()) :: Request.t()
  def insert_request(bucket, metadata, bytes, query \\ [], opts \\ []) do
    boundary = Keyword.get_lazy(opts, :boundary, &generate_boundary/0)

    body = [
      "--",
      boundary,
      "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n",
      json_codec(opts).encode!(metadata),
      "\r\n--",
      boundary,
      "\r\nContent-Type: ",
      media_content_type(metadata),
      "\r\n\r\n",
      bytes,
      "\r\n--",
      boundary,
      "--\r\n"
    ]

    %Request{
      method: :post,
      url: base_url(opts) <> "/upload/storage/v1/b/" <> encode(bucket) <> "/o",
      query: [uploadType: "multipart"] ++ query,
      headers: [{"content-type", "multipart/related; boundary=" <> boundary}],
      body: body
    }
  end

  @doc false
  @spec get_request(String.t(), String.t(), keyword()) :: Request.t()
  def get_request(bucket, name, query \\ []) do
    %Request{method: :get, url: object_url(bucket, name, []), query: query}
  end

  @doc false
  @spec delete_request(String.t(), String.t()) :: Request.t()
  def delete_request(bucket, name) do
    %Request{method: :delete, url: object_url(bucket, name, [])}
  end

  @doc false
  @spec list_request(String.t(), keyword()) :: Request.t()
  def list_request(bucket, query \\ []) do
    %Request{
      method: :get,
      url: base_url([]) <> "/storage/v1/b/" <> encode(bucket) <> "/o",
      query: query
    }
  end

  defp object_url(bucket, name, opts) do
    base_url(opts) <> "/storage/v1/b/" <> encode(bucket) <> "/o/" <> encode(name)
  end

  defp encode(segment), do: Util.encode_object_name(segment)

  defp read_data({:file, path}), do: File.read!(path)
  defp read_data({:binary, data}), do: data

  defp media_content_type(metadata) do
    content_type = metadata[:contentType] || metadata["contentType"] || "application/octet-stream"

    unless is_binary(content_type) and content_type =~ ~r/^[\x20-\x7e]+$/ do
      raise ArgumentError, "invalid contentType for upload: #{inspect(content_type)}"
    end

    content_type
  end

  defp generate_boundary do
    "waffle_gcs_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  defp execute(%Request{} = request, opts) do
    transport =
      opts[:transport] ||
        Application.get_env(:waffle_gcs, :transport, Waffle.Storage.Google.Transport.Req)

    transport.execute(authorize(request, opts), opts)
  end

  defp authorize(%Request{} = request, opts) do
    token_fetcher = Application.fetch_env!(:waffle, :token_fetcher)
    scope = Keyword.get(opts, :scope, @full_control_scope)
    token = token_fetcher.get_token(scope)

    %{request | headers: [{"authorization", "Bearer " <> token} | request.headers]}
  end

  defp map_object({:ok, %Response{status: status, body: body} = response}, opts)
       when status in 200..299 do
    {:ok, body |> json_codec(opts).decode!() |> Object.from_map(response)}
  end

  defp map_object(other, opts), do: {:error, to_error(other, opts)}

  defp to_error({:ok, %Response{} = response}, opts) do
    Error.from_response(response, json_codec(opts))
  end

  defp to_error({:error, reason}, _opts) do
    %Error{status: nil, reason: reason, raw: nil}
  end

  defp json_codec(opts) do
    opts[:json_codec] || Application.get_env(:waffle_gcs, :json_codec, Jason)
  end

  defp base_url(opts) do
    opts[:base_url] || Application.get_env(:waffle_gcs, :base_url, @base_url)
  end
end
