defmodule Waffle.Storage.Google.CloudStorage do
  @moduledoc """
  The main storage integration for Waffle, backed by the built-in GCS client
  (`Waffle.Storage.Google.Client`). To use this module with Waffle, simply set
  your `:storage` config appropriately:

  ```elixir
  config :waffle, storage: Waffle.Storage.Google.CloudStorage
  ```

  Ensure you have a valid bucket set, either through the configs or as an
  environment variable, otherwise all calls will fail. The credentials available
  through `Goth` must have the appropriate level of access to the bucket,
  otherwise some (or all) calls may fail.

  ## ACLs

  A definition's `acl/2` may return:

    * an atom (`:public_read`, `:authenticated_read`, `:bucket_owner_read`,
      `:bucket_owner_full_control`, `:project_private`) — sent as the
      `predefinedAcl` query parameter
    * `:private` or `nil` — nothing is sent and the bucket's default applies,
      which is required for buckets with uniform bucket-level access
    * a string — sent as `predefinedAcl` verbatim
    * a list of ACL entries (maps) — sent as the object resource's `acl` field
      (fine-grained buckets only)
  """

  alias Waffle.Storage.Google.{Client, Error, Object, Util}
  alias Waffle.Types

  @type object_or_error :: {:ok, Object.t()} | {:error, Error.t()}

  @predefined_acls %{
    authenticated_read: "authenticatedRead",
    bucket_owner_full_control: "bucketOwnerFullControl",
    bucket_owner_read: "bucketOwnerRead",
    project_private: "projectPrivate",
    public_read: "publicRead"
  }

  @doc """
  Put a Waffle file in a Google Cloud Storage bucket.
  """
  @spec put(Types.definition(), Types.version(), Types.meta()) :: object_or_error
  def put(definition, version, meta) do
    {file, _scope} = meta
    destination_dir = storage_dir(definition, version, meta)
    # Explicitly not `path_for`.
    # Waffle will have already called `Versioning.resolve_file_name` when calling `definition.store`
    path = Path.join(destination_dir, file.file_name)

    {acl_metadata, acl_query} = acl_params(definition.acl(version, meta))

    metadata =
      definition
      |> optional_callback(:gcs_object_headers, [version, meta])
      |> ensure_keyword_list()
      # GCS stores objects without a content type as application/octet-stream,
      # so infer one from the filename unless the definition's headers set it.
      |> Keyword.put_new(:contentType, MIME.from_path(file.file_name))
      |> Keyword.merge(acl_metadata)
      |> Map.new()

    query =
      definition
      |> optional_callback(:gcs_optional_params, [version, meta])
      |> ensure_keyword_list()
      |> then(&Keyword.merge(acl_query, &1))

    Client.insert(bucket(definition, meta), path, data(meta), metadata: metadata, query: query)
  end

  @doc """
  Delete a file from a Google Cloud Storage bucket.
  """
  @spec delete(Types.definition(), Types.version(), Types.meta()) :: :ok | {:error, Error.t()}
  def delete(definition, version, meta) do
    Client.delete(bucket(definition, meta), path_for(definition, version, meta))
  end

  @doc """
  Retrieve the public URL for a file in a Google Cloud Storage bucket. Uses
  `Waffle.Storage.Google.UrlV2` by default, which uses v2 signing if a signed
  URL is requested, but this can be overriden in the options list or in the
  application configs by setting `:url_builder` to any module that imlements the
  behavior of `Waffle.Storage.Google.Url`.
  """
  @spec url(Types.definition(), Types.version(), Types.meta(), Keyword.t()) :: String.t()
  def url(definition, version, meta, opts \\ []) do
    signer = Util.option(opts, :url_builder, Waffle.Storage.Google.UrlV2)
    signer.build(definition, version, meta, opts)
  end

  @doc """
  Returns the bucket for file uploads.

  When `meta` (`{file, scope}`) is given, the definition's `bucket/1` callback
  is preferred — matching the S3 adapter — so a definition can select a bucket
  per file/scope:

  ```elixir
  def bucket({_file, scope}), do: scope.bucket || bucket()
  ```

  `bucket/0` remains the fallback for waffle versions whose definitions don't
  export `bucket/1`.
  """
  @spec bucket(Types.definition(), Types.meta() | nil) :: String.t()
  def bucket(definition, meta \\ nil)
  def bucket(definition, nil), do: Util.var(definition.bucket())

  def bucket(definition, meta) do
    if Code.ensure_loaded?(definition) and function_exported?(definition, :bucket, 1) do
      Util.var(definition.bucket(meta))
    else
      Util.var(definition.bucket())
    end
  end

  @doc """
  Returns the storage directory **within a bucket** to store the file under.
  """
  @spec storage_dir(Types.definition(), Types.version(), Types.meta()) :: String.t()
  def storage_dir(definition, version, meta) do
    version
    |> definition.storage_dir(meta)
    |> Util.var()
  end

  @doc """
  Returns the full file path for the upload destination.
  """
  @spec path_for(Types.definition(), Types.version(), Types.meta()) :: String.t()
  def path_for(definition, version, meta) do
    definition
    |> storage_dir(version, meta)
    |> Path.join(fullname(definition, version, meta))
  end

  @doc """
  A wrapper for `Waffle.Definition.Versioning.resolve_file_name/3`.
  """
  @spec fullname(Types.definition(), Types.version(), Types.meta()) :: String.t()
  def fullname(definition, version, meta) do
    Waffle.Definition.Versioning.resolve_file_name(definition, version, meta)
  end

  @spec data({Types.file(), String.t()}) :: Client.data()
  defp data({%{binary: nil, path: path}, _}), do: {:file, path}
  defp data({%{binary: data}, _}), do: {:binary, data}

  @spec acl_params(term()) :: {Keyword.t(), Keyword.t()}
  defp acl_params(nil), do: {[], []}
  defp acl_params(:private), do: {[], []}

  defp acl_params(acl) when is_atom(acl) do
    case @predefined_acls do
      %{^acl => predefined} ->
        {[], [predefinedAcl: predefined]}

      _ ->
        raise ArgumentError,
              "unsupported ACL #{inspect(acl)}; supported atoms: " <>
                "#{inspect([:private | Map.keys(@predefined_acls)])}, " <>
                "a predefinedAcl string, or a list of ACL entries"
    end
  end

  defp acl_params(acl) when is_binary(acl), do: {[], [predefinedAcl: acl]}
  defp acl_params(acl) when is_list(acl), do: {[acl: acl], []}

  defp optional_callback(definition, fun, args) do
    if Code.ensure_loaded?(definition) and function_exported?(definition, fun, length(args)) do
      apply(definition, fun, args)
    else
      []
    end
  end

  defp ensure_keyword_list(list) when is_list(list), do: list
  defp ensure_keyword_list(map) when is_map(map), do: Map.to_list(map)
end
