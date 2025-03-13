defmodule Waffle.Storage.Google.CloudStorageTest do
  use ExUnit.Case, async: false

  alias Waffle.Storage.Google.CloudStorage

  @moduletag :tmp_dir

  @file_name "image.png"
  @file_path "test/support/#{@file_name}"

  @img "test/support/image.png"
  @img_with_space "test/support/image two.png"
  @img_with_plus "test/support/image+three.png"
  @dummy_content_disposition "attachment; filename=\"abc.png\""

  setup meta do
    [_, unique_storage_dir] = :string.split(meta.tmp_dir, "/tmp/")
    [mod_str, test_str] = Path.split(unique_storage_dir)

    unique_basename = mod_str <> "__" <> test_str
    tmp_path = Path.join(meta.tmp_dir, unique_basename <> ".png")

    File.cp!(@img, tmp_path)
    on_exit(:cleanup_local_tmp_files, fn -> File.rm!(tmp_path) end)

    [unique_basename: unique_basename, tmp_path: tmp_path]
  end

  def env_bucket(), do: System.fetch_env!("WAFFLE_BUCKET")

  def bucket_url(bucket \\ env_bucket()) do
    "https://storage.googleapis.com/#{bucket}"
  end

  def random_hex, do: 8 |> :crypto.strong_rand_bytes() |> Base.encode16()

  def random_name(_) do
    name = random_hex()
    %{name: name, path: "uploads/#{name}.png"}
  end

  def create_wafile(%{tmp_path: tmp_path}) do
    %{wafile: Waffle.File.new(tmp_path, DummyDefinition)}
  end

  def setup_waffle(%{wafile: file, name: name}) do
    %{
      version: :original,
      meta: {file, name}
    }
  end

  def cleanup(_) do
    # We should prefer, for performance reasons, to cleanup the bucket once
    # after all tests have run, but `after_suite/1` is only available starting
    # with Elixir version 1.8.0. Therefore, previous versions need to use the
    # `on_exit/1` function to register a callback that executes after each
    # individual test runs.
    if Version.compare(System.version(), "1.8.0") == :lt do
      on_exit(fn -> IO.puts("Cleanup invokved (#{inspect(self())})") end)
    else
      :ok
    end
  end

  describe "conn/1" do
    @describetag skip: "Deprecate"
    test "constructs a Tesla client" do
      assert %Tesla.Client{} = CloudStorage.conn()
    end

    test "constructs a Tesla client with a custom scope" do
      assert %Tesla.Client{} =
               CloudStorage.conn("https://www.googleapis.com/auth/devstorage.read_only")
    end
  end

  describe "utility functions" do
    @describetag definition: DummyDefinition

    setup [:random_name, :create_wafile, :setup_waffle]

    test "bucket/1 returns a bucket name based on a Waffle definition", %{definition: def} do
      assert env_bucket() == CloudStorage.bucket(def)
      assert "invalid" == CloudStorage.bucket(DummyDefinitionInvalidBucket)
    end

    @tag skip: "Deprecate"
    test "storage_dir/3 returns the remote storage directory (not the bucket)", %{
      definition: def,
      version: ver,
      meta: meta
    } do
      assert "uploads" == CloudStorage.storage_dir(def, ver, meta)
    end

    test "path_for/3 returns the file full path (storage directory plus filename)", %{
      definition: def,
      version: ver,
      meta: meta,
      path: path
    } do
      assert path == CloudStorage.path_for(def, ver, meta)
    end
  end

  describe "waffle functions" do
    @describetag definition: DummyDefinition

    setup [:random_name, :create_wafile, :setup_waffle]

    test "put/3 uploads a valid file", %{definition: def, version: ver, meta: meta} do
      assert {:ok, _} = CloudStorage.put(def, ver, meta)
    end

    test "put/3 uploads binary data", test_meta do
      %{version: ver, unique_basename: name, tmp_path: file_path} = test_meta

      assert {:ok, _} =
               CloudStorage.put(
                 test_meta.definition,
                 ver,
                 {%Waffle.File{binary: File.read!(file_path), file_name: "#{name}.png"}, name}
               )
    end

    test "put/3 fails for an invalid file", %{version: ver, meta: meta} do
      assert {:error, _} = CloudStorage.put(DummyDefinitionInvalidBucket, ver, meta)
    end

    test "delete/3 fails for invalid bucket or object", %{
      definition: def,
      version: ver,
      meta: meta
    } do
      assert {:error, _} = CloudStorage.delete(def, ver, meta)
      assert {:error, _} = CloudStorage.delete(DummyDefinitionInvalidBucket, ver, meta)
    end

    test "url/3 returns regular URLs", %{definition: def, version: ver, meta: meta, name: name} do
      assert CloudStorage.url(def, ver, meta) =~ "/#{env_bucket()}/uploads/#{name}"
    end

    test "url/3 returns CDN URL without bucket name in path", %{
      definition: def,
      version: ver,
      meta: meta,
      name: name
    } do
      Application.put_env(:waffle, :asset_host, "cdn-domain.com")

      assert CloudStorage.url(def, ver, meta) ==
               "https://cdn-domain.com/uploads/#{name}.png"

      Application.delete_env(:waffle, :asset_host)
    end
  end

  defmacro delete_and_assert_not_found(definition, args) do
    quote bind_quoted: [definition: definition, args: args] do
      :ok = definition.delete(args)
      signed_url = definition.url(args, signed: true)
      {:ok, {{_, code, msg}, _, _}} = :httpc.request(to_charlist(signed_url))

      # If buckets aren't configured to be public at bucket-level,
      # deleted objects may return 403 Forbidden instead of 404 Not Found,
      # even with a signed url
      assert code in [403, 404]
    end
  end

  defmacro assert_header(definition, args, header, value) do
    quote bind_quoted: [definition: definition, args: args, header: header, value: value] do
      url = definition.url(args)
      {:ok, {{_, 200, ~c"OK"}, headers, _}} = :httpc.request(to_charlist(url))

      char_header = to_charlist(header)

      assert to_charlist(value) ==
               Enum.find_value(headers, fn
                 {^char_header, value} -> value
                 _ -> nil
               end)
    end
  end

  defmacro assert_acls_public_reader(definition, args) do
    quote bind_quoted: [definition: definition, args: args] do
      "uploads/#{args}" |> IO.inspect()

      {:ok, %GoogleApi.Storage.V1.Model.ObjectAccessControls{} = acls} =
        GoogleApi.Storage.V1.Api.ObjectAccessControls.storage_object_access_controls_list(
          CloudStorage.conn(),
          CloudStorage.bucket(definition),
          "uploads/#{args}"
        )

      assert [
               %{role: "OWNER", entity: service_account},
               %{role: "READER", entity: "allUsers"}
             ] = acls.items |> Enum.sort_by(& &1.role)

      assert service_account =~ ".iam.gserviceaccount.com"
    end
  end

  defmacro assert_private(definition, args) do
    quote bind_quoted: [definition: definition, args: args] do
      unsigned_url = definition.url(args)
      {:ok, {{_, code, msg}, _, _}} = :httpc.request(to_charlist(unsigned_url))
      assert code == 403
      assert msg == ~c"Forbidden"

      signed_url = definition.url(args, signed: true)
      {:ok, {{_, code, msg}, headers, _}} = :httpc.request(to_charlist(signed_url))
      assert code == 200
      assert msg == ~c"OK"
    end
  end

  defmacro assert_public(definition, args) do
    quote bind_quoted: [definition: definition, args: args] do
      url = definition.url(args)
      {:ok, {{_, code, msg}, headers, _}} = :httpc.request(to_charlist(url))
      assert code == 200
      assert msg == ~c"OK"
    end
  end

  defmacro assert_public_with_extension(definition, args, version, extension) do
    quote bind_quoted: [
            definition: definition,
            version: version,
            args: args,
            extension: extension
          ] do
      url = definition.url(args, version)
      {:ok, {{_, code, msg}, headers, _}} = :httpc.request(to_charlist(url))
      assert code == 200
      assert msg == ~c"OK"
      assert Path.extname(url) == extension
    end
  end

  setup_all do
    Application.ensure_all_started(:hackney)
    Application.put_env(:waffle, :virtual_host, true)
    Application.put_env(:waffle, :bucket, {:system, "WAFFLE_BUCKET"})
  end

  def with_env(app, key, value, fun) do
    previous = Application.get_env(app, key, :nothing)

    Application.put_env(app, key, value)

    try do
      fun.()
    rescue
      e -> raise(e)
    after
      case previous do
        :nothing -> Application.delete_env(app, key)
        _ -> Application.put_env(app, key, previous)
      end
    end
  end

  describe "from upstream storage tests" do
    @describetag :from_upstream
    @describetag :tmp_dir

    @tag skip: "TODO - determine if this is relevant to GCS"
    @tag timeout: 15_000
    test "custom asset_host" do
      custom_asset_host = "https://some.cloudfront.com"

      with_env(:waffle, :asset_host, custom_asset_host, fn ->
        assert "#{custom_asset_host}/uploads/image.png" ==
                 NewDummyDefinition.url(@img)
      end)

      with_env(:waffle, :asset_host, {:system, "WAFFLE_ASSET_HOST"}, fn ->
        System.put_env("WAFFLE_ASSET_HOST", custom_asset_host)

        assert "#{custom_asset_host}/uploads/image.png" ==
                 NewDummyDefinition.url(@img)
      end)

      with_env(:waffle, :asset_host, false, fn ->
        assert "#{bucket_url()}/uploads/image.png" == NewDummyDefinition.url(@img)
      end)
    end

    @tag skip: "TODO - determine if this is relevant to GCS"
    @tag timeout: 150_000
    test "custom asset_host in definition" do
      custom_asset_host = "https://example.com"

      assert "#{custom_asset_host}/uploads/image.png" == DefinitionWithAssetHost.url(@img)
    end

    @tag timeout: 15_000
    test "encoded url" do
      assert "#{bucket_url()}/uploads/image%20two.png" == NewDummyDefinition.url(@img_with_space)
    end

    @tag skip: "TODO - determine if this is relevant to GCS"
    @tag timeout: 15_000
    test "encoded url with S3-specific escaping" do
      assert "#{bucket_url()}/uploads/image%2Bthree.png" == NewDummyDefinition.url(@img_with_plus)
    end

    @tag timeout: 15_000
    test "public put and get", meta do
      assert {:ok, uploaded_filename} = NewDummyDefinition.store(meta.tmp_path)
      assert uploaded_filename == uploaded_filename
      assert_public(NewDummyDefinition, uploaded_filename)
      delete_and_assert_not_found(NewDummyDefinition, uploaded_filename)
    end

    @tag timeout: 15_000
    test "private put and signed get", meta do
      # put the image as private
      assert {:ok, uploaded_filename} = NewDummyDefinition.store({meta.tmp_path, :private})
      assert uploaded_filename == meta.unique_basename <> ".png"
      assert_private(NewDummyDefinition, uploaded_filename)
      delete_and_assert_not_found(NewDummyDefinition, uploaded_filename)
    end

    @tag timeout: 15_000
    test "content_type", meta do
      assert {:ok, uploaded_filename} =
               NewDummyDefinition.store({meta.tmp_path, :with_content_type})

      assert uploaded_filename == meta.unique_basename <> ".png"
      uploaded_filename |> IO.inspect()

      assert_acls_public_reader(NewDummyDefinition, uploaded_filename)
      assert_header(NewDummyDefinition, uploaded_filename, "content-type", "image/gif")
      delete_and_assert_not_found(NewDummyDefinition, uploaded_filename)
    end

    @tag timeout: 15_000
    test "content_disposition", meta do
      assert {:ok, uploaded_filename} =
               NewDummyDefinition.store({meta.tmp_path, :with_content_disposition})

      assert uploaded_filename == meta.unique_basename <> ".png"

      assert_acls_public_reader(NewDummyDefinition, uploaded_filename)

      assert_header(
        NewDummyDefinition,
        uploaded_filename,
        "content-disposition",
        @dummy_content_disposition
      )

      delete_and_assert_not_found(NewDummyDefinition, uploaded_filename)
    end

    @tag timeout: 150_000
    test "with concatenated filename", meta do
      mod = DefinitionWithConcatenatedFilename

      scope = %{id: 1}
      assert {:ok, uploaded_filename} = mod.store({meta.tmp_path, scope})
      assert uploaded_filename == meta.unique_basename <> ".png"

      assert mod.url({uploaded_filename, scope}, :original) ==
               "#{bucket_url()}/uploads/1_original_" <> uploaded_filename

      assert mod.url({uploaded_filename, scope}, :thumb) ==
               "#{bucket_url()}/uploads/1_thumb_" <> uploaded_filename

      assert mod.url({uploaded_filename, scope}) ==
               "#{bucket_url()}/uploads/1_original_" <> uploaded_filename

      assert_public_with_extension(mod, {uploaded_filename, scope}, :original, ".png")
      assert_public_with_extension(mod, {uploaded_filename, scope}, :thumb, ".png")
      delete_and_assert_not_found(mod, {uploaded_filename, scope})
    end

    @tag timeout: 150_000
    test "delete with scope", meta do
      mod = DefinitionWithScope

      scope = %{id: 1}
      assert {:ok, uploaded_filename} = mod.store({meta.tmp_path, scope})
      assert uploaded_filename == meta.unique_basename <> ".png"

      assert mod.url({uploaded_filename, scope}) ==
               "#{bucket_url()}/uploads/with_scopes/1/" <> uploaded_filename

      assert_public(mod, {uploaded_filename, scope})
      assert_acls_public_reader(mod, "with_scopes/1/" <> uploaded_filename)
      delete_and_assert_not_found(mod, {uploaded_filename, scope})
    end

    @tag upstream_mismatch: "This is a bug w/ bucket/1 not being implemented. To be resolved"
    @tag :bucket_with_file_and_scope
    @tag timeout: 150_000
    test "delete with bucket in scope" do
      mod = DefinitionWithBucketInScope

      bucket = System.fetch_env!("WAFFLE_BUCKET2")
      scope = %{id: 1, bucket: bucket}
      {:ok, path} = mod.store({"test/support/image.png", scope})

      assert mod.url({path, scope}) ==
               "#{bucket_url(bucket)}/uploads/image.png"

      assert_public(mod, {path, scope})
      delete_and_assert_not_found(mod, {path, scope})
    end

    @tag timeout: 150_000
    test "with bucket", meta do
      mod = DefinitionWithBucket

      url = "#{bucket_url()}/uploads/" <> meta.unique_basename <> ".png"
      assert url == mod.url(meta.tmp_path)
      assert {:ok, uploaded_filename} = mod.store(meta.tmp_path)
      assert uploaded_filename == meta.unique_basename <> ".png"
      delete_and_assert_not_found(mod, meta.tmp_path)
    end

    @tag timeout: 150_000
    test "put with error" do
      mod = NewDummyDefinition

      with_env(:waffle, :bucket, "unknown-bucket", fn ->
        {:error, res} = mod.store("test/support/image.png")
        assert res
      end)
    end

    @tag timeout: 150_000
    test "put with converted version", meta do
      mod = DefinitionWithThumbnail

      assert {:ok, uploaded_filename} = mod.store(meta.tmp_path)
      assert uploaded_filename == meta.unique_basename <> ".png"
      assert_public_with_extension(mod, uploaded_filename, :thumb, ".jpg")
      delete_and_assert_not_found(mod, uploaded_filename)
    end

    @tag timeout: 150_000
    test "url for a skipped version" do
      assert nil == DefinitionWithSkipped.url("image.png")
    end
  end
end
