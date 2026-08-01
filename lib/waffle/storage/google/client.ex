defmodule Waffle.Storage.Google.Client do
  @moduledoc """
  Minimal GCS JSON API client backing the Waffle adapter: the four operations
  the adapter needs, built as data and executed by the configured
  `Waffle.Storage.Google.Transport`.

  Results are library-owned types: `Waffle.Storage.Google.Object` on success
  and `Waffle.Storage.Google.Error` on failure, both carrying the transport
  response under `:response`.

  Configuration (all optional):

  ```elixir
  config :waffle_gcs,
    transport: Waffle.Storage.Google.Transport.Req,
    json_codec: Jason,
    base_url: "https://storage.googleapis.com"
  ```

  Every option can also be passed per call (`:transport`, `:json_codec`,
  `:base_url`, `:scope`).

  Map keys and query parameters use the GCS JSON API's own names verbatim
  (`contentType`, `predefinedAcl`, `pageToken`, ...) — they are wire-protocol
  identifiers, not Elixir ones, and consumers already pass them through
  `gcs_object_headers/2` and `gcs_optional_params/2` in that spelling.
  """

  alias Waffle.Storage.Google.{Error, Object, Util}
  alias Waffle.Storage.Google.Client.{Request, Response}

  @base_url "https://storage.googleapis.com"
  @full_control_scope "https://www.googleapis.com/auth/devstorage.full_control"
  @default_json_codec Jason
  @default_transport Waffle.Storage.Google.Transport.Req

  @type data :: {:file, Path.t()} | {:binary, binary()}
  @type object_result :: {:ok, Object.t()} | {:error, Error.t()}

  @typedoc "Per-call options resolved once against application config; see `build_config/1`."
  @type config :: %{
          transport: module(),
          json_codec: module(),
          base_url: String.t(),
          scope: String.t(),
          boundary: String.t() | nil
        }

  @doc """
  Resolves per-call options against application config and defaults, once,
  so the resolution cost and precedence live in a single place.
  """
  @spec build_config(keyword()) :: config()
  def build_config(opts \\ []) do
    %{
      transport: resolve(opts, :transport, @default_transport),
      json_codec: resolve(opts, :json_codec, @default_json_codec),
      base_url: resolve(opts, :base_url, @base_url),
      scope: Keyword.get(opts, :scope, @full_control_scope),
      boundary: Keyword.get(opts, :boundary)
    }
  end

  defp resolve(opts, key, default) do
    opts[key] || Application.get_env(:waffle_gcs, key, default)
  end

  @doc """
  Uploads an object in a single `multipart/related` request.

  `:metadata` is the object resource sent as the JSON part (`name` is set from
  `name`); entries like `contentType` and `acl` go here. `:query` passes extra
  query parameters (e.g. `predefinedAcl: "publicRead"`).
  """
  @spec insert(String.t(), String.t(), data(), keyword()) :: object_result()
  def insert(bucket, name, data, opts \\ []) do
    config = build_config(opts)

    metadata =
      opts
      |> Keyword.get(:metadata, %{})
      |> normalize_metadata()
      |> Map.put("name", name)

    bucket
    |> insert_request(metadata, read_data(data), Keyword.get(opts, :query, []), config)
    |> execute(config, opts)
    |> map_object(config)
  end

  @doc """
  Fetches an object's metadata. Pass `query: [projection: "full"]` to include
  ACLs.
  """
  @spec get(String.t(), String.t(), keyword()) :: object_result()
  def get(bucket, name, opts \\ []) do
    config = build_config(opts)

    bucket
    |> get_request(name, Keyword.get(opts, :query, []), config)
    |> execute(config, opts)
    |> map_object(config)
  end

  @doc """
  Deletes an object.
  """
  @spec delete(String.t(), String.t(), keyword()) :: :ok | {:error, Error.t()}
  def delete(bucket, name, opts \\ []) do
    config = build_config(opts)

    bucket
    |> delete_request(name, config)
    |> execute(config, opts)
    |> case do
      {:ok, %Response{status: status}} when status in 200..299 -> :ok
      other -> {:error, to_error(other, config)}
    end
  end

  @doc """
  Lists objects in a bucket. Supports `query: [prefix: ..., pageToken: ...]`.

  Returns `{:ok, %{items: [Object.t()], next_page_token: String.t() | nil}}`;
  listed objects carry `response: nil`.
  """
  @spec list(String.t(), keyword()) ::
          {:ok, %{items: [Object.t()], next_page_token: String.t() | nil}} | {:error, Error.t()}
  def list(bucket, opts \\ []) do
    config = build_config(opts)

    bucket
    |> list_request(Keyword.get(opts, :query, []), config)
    |> execute(config, opts)
    |> case do
      {:ok, %Response{status: status, body: body}} when status in 200..299 ->
        decoded = config.json_codec.decode!(body)

        {:ok,
         %{
           items: decoded |> Map.get("items", []) |> Enum.map(&Object.from_map/1),
           next_page_token: decoded["nextPageToken"]
         }}

      other ->
        {:error, to_error(other, config)}
    end
  end

  @doc """
  Builds the `multipart/related` insert request.

  The multipart framing is entirely library-controlled: a random boundary and
  constant part headers, except the media part's `Content-Type`, which mirrors
  the metadata's `contentType` (as `google_gax` did) and is validated to be a
  single printable-ASCII line.
  """
  @spec insert_request(String.t(), map(), iodata(), keyword(), config()) :: Request.t()
  def insert_request(bucket, metadata, bytes, query \\ [], config \\ build_config()) do
    metadata = normalize_metadata(metadata)
    boundary = config.boundary || generate_boundary()

    body = [
      "--",
      boundary,
      "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n",
      config.json_codec.encode!(metadata),
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
      url: config.base_url <> "/upload/storage/v1/b/" <> encode(bucket) <> "/o",
      query: [{:uploadType, "multipart"} | query],
      headers: [{"content-type", "multipart/related; boundary=" <> boundary}],
      body: body
    }
  end

  @doc false
  @spec get_request(String.t(), String.t(), keyword(), config()) :: Request.t()
  def get_request(bucket, name, query \\ [], config \\ build_config()) do
    %Request{method: :get, url: object_url(bucket, name, config), query: query}
  end

  @doc false
  @spec delete_request(String.t(), String.t(), config()) :: Request.t()
  def delete_request(bucket, name, config \\ build_config()) do
    %Request{method: :delete, url: object_url(bucket, name, config)}
  end

  @doc false
  @spec list_request(String.t(), keyword(), config()) :: Request.t()
  def list_request(bucket, query \\ [], config \\ build_config()) do
    %Request{
      method: :get,
      url: config.base_url <> "/storage/v1/b/" <> encode(bucket) <> "/o",
      query: query
    }
  end

  defp object_url(bucket, name, config) do
    config.base_url <> "/storage/v1/b/" <> encode(bucket) <> "/o/" <> encode(name)
  end

  defp encode(segment), do: Util.encode_object_name(segment)

  defp normalize_metadata(metadata) do
    Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  end

  defp read_data({:file, path}), do: File.read!(path)
  defp read_data({:binary, data}), do: data

  @ascii_printable_chars 32..126

  defp printable_ascii_line?(<<byte>>) when byte in @ascii_printable_chars, do: true

  defp printable_ascii_line?(<<byte, rest::binary>>) when byte in @ascii_printable_chars,
    do: printable_ascii_line?(rest)

  defp printable_ascii_line?(_), do: false

  defp media_content_type(metadata) do
    content_type = metadata["contentType"] || "application/octet-stream"

    if printable_ascii_line?(content_type) do
      content_type
    else
      raise ArgumentError, "invalid contentType for upload: #{inspect(content_type)}"
    end
  end

  defp generate_boundary do
    "waffle_gcs_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  defp execute(%Request{} = request, config, opts) do
    config.transport.execute(authorize(request, config), opts)
  end

  defp authorize(%Request{} = request, config) do
    token_fetcher = Application.fetch_env!(:waffle, :token_fetcher)
    token = token_fetcher.get_token(config.scope)

    %{request | headers: [{"authorization", "Bearer " <> token} | request.headers]}
  end

  defp map_object({:ok, %Response{status: status, body: body} = response}, config)
       when status in 200..299 do
    {:ok, body |> config.json_codec.decode!() |> Object.from_map(response)}
  end

  defp map_object(other, config), do: {:error, to_error(other, config)}

  defp to_error({:ok, %Response{} = response}, config) do
    Error.from_response(response, config.json_codec)
  end

  defp to_error({:error, reason}, _config) do
    %Error{status: nil, reason: reason, response: nil}
  end
end
