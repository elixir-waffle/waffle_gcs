defmodule Waffle.Storage.Google.CloudStorageTest do
  # Tests the `CloudStorage` module's API directly (as opposed to the public
  # `definition.store/url/delete` flow, which is covered by the integration suite
  # under test/integration/). Path/name construction is exercised as pure unit
  # tests; the put/delete/url round-trips are tagged `:integration` (real GCS).
  use ExUnit.Case, async: false

  alias Waffle.Storage.Google.{CloudStorage, Error, Object}
  alias Waffle.Storage.Google.Client.{Request, Response}

  @file_path "test/support/image.png"

  defmodule StubFetcher do
    @behaviour Waffle.Storage.Google.Token.Fetcher
    @impl true
    def get_token(_scope), do: "stub-token"
  end

  defmodule CaptureTransport do
    @behaviour Waffle.Storage.Google.Transport

    @impl true
    def execute(request, _opts) do
      send(self(), {:request, request})
      {:ok, %Response{status: 200, headers: [], body: ~s({"name": "captured"})}}
    end
  end

  defmodule AclAtom do
    use Waffle.Definition
    @acl :public_read
    def bucket, do: "offline-bucket"
  end

  defmodule AclDefault do
    use Waffle.Definition
    def bucket, do: "offline-bucket"
  end

  defmodule AclString do
    use Waffle.Definition
    def bucket, do: "offline-bucket"
    def acl(_version, _meta), do: "bucketOwnerRead"
  end

  defmodule AclList do
    use Waffle.Definition
    @acl [%{entity: "allUsers", role: "READER"}]
    def bucket, do: "offline-bucket"
  end

  defmodule AclUnknown do
    use Waffle.Definition
    @acl :public_read_write
    def bucket, do: "offline-bucket"
  end

  defmodule AclOverriddenByParams do
    use Waffle.Definition
    @acl :public_read
    def bucket, do: "offline-bucket"
    def gcs_optional_params(_version, _meta), do: [predefinedAcl: "private", userProject: "p"]
  end

  defmodule StringKeyHeaders do
    use Waffle.Definition
    def bucket, do: "offline-bucket"
    def gcs_object_headers(_version, _meta), do: %{"contentType" => "image/webp"}
  end

  defmodule RaisingHeaders do
    use Waffle.Definition
    def bucket, do: "offline-bucket"
    def gcs_object_headers(_version, _meta), do: apply(:"#{__MODULE__}.Missing", :boom, [])
  end

  defmodule RaisingParams do
    use Waffle.Definition
    def bucket, do: "offline-bucket"
    def gcs_optional_params(_version, _meta), do: apply(:"#{__MODULE__}.Missing", :boom, [])
  end

  setup_all do
    Application.ensure_all_started(:hackney)
    Application.put_env(:waffle, :virtual_host, true)
    Application.put_env(:waffle, :bucket, {:system, "WAFFLE_BUCKET"})
    :ok
  end

  # ── Pure unit: path & name construction (no network, no creds) ────────────

  describe "storage_dir/3" do
    test "returns the definition's storage directory (not the bucket)" do
      meta = {%Waffle.File{file_name: "image.png"}, nil}

      assert GCSTest.Run.storage_dir() ==
               CloudStorage.storage_dir(GCSTest.PublicUpload, :original, meta)
    end
  end

  describe "path_for/3" do
    test "joins the storage directory and the resolved filename" do
      meta = {%Waffle.File{file_name: "image.png"}, nil}

      assert "#{GCSTest.Run.storage_dir()}/image.png" ==
               CloudStorage.path_for(GCSTest.PublicUpload, :original, meta)
    end

    test "applies a custom filename/2 exactly once" do
      meta = {%Waffle.File{file_name: "image.png"}, %{id: 7}}

      assert "#{GCSTest.Run.storage_dir()}/7_image.png" ==
               CloudStorage.path_for(GCSTest.WithCustomFilename, :original, meta)
    end
  end

  describe "bucket/1" do
    test "resolves a literal bucket from the definition" do
      assert "invalid" == CloudStorage.bucket(GCSTest.InvalidBucket)
    end
  end

  describe "bucket/2" do
    test "selects the bucket from scope when the definition supports it" do
      meta = {%Waffle.File{file_name: "image.png"}, %{bucket: "scope-bucket"}}

      assert "scope-bucket" == CloudStorage.bucket(GCSTest.WithBucketInScope, meta)
    end

    test "ignores the scope for a definition without scope-based bucket selection" do
      meta = {%Waffle.File{file_name: "image.png"}, %{bucket: "ignored"}}

      assert "invalid" == CloudStorage.bucket(GCSTest.InvalidBucket, meta)
    end
  end

  # ── Offline: put/3 request assembly ──────────────────────────────────────

  describe "put/3 request assembly" do
    setup do
      original = Application.fetch_env!(:waffle, :token_fetcher)
      Application.put_env(:waffle, :token_fetcher, StubFetcher)
      Application.put_env(:waffle_gcs, :transport, CaptureTransport)

      on_exit(fn ->
        Application.put_env(:waffle, :token_fetcher, original)
        Application.delete_env(:waffle_gcs, :transport)
      end)

      %{meta: {%Waffle.File{file_name: "img.png", binary: "BYTES"}, nil}}
    end

    defp captured_request do
      assert_received {:request, %Request{} = request}
      request
    end

    defp metadata_json(%Request{body: body}) do
      [_, json] = Regex.run(~r/charset=UTF-8\r\n\r\n(.*?)\r\n--/s, IO.iodata_to_binary(body))
      Jason.decode!(json)
    end

    test "an atom ACL becomes the predefinedAcl query parameter", %{meta: meta} do
      {:ok, _} = CloudStorage.put(AclAtom, :original, meta)
      request = captured_request()

      assert request.query[:predefinedAcl] == "publicRead"
      refute Map.has_key?(metadata_json(request), "acl")
    end

    test "the default :private ACL sends nothing", %{meta: meta} do
      {:ok, _} = CloudStorage.put(AclDefault, :original, meta)
      request = captured_request()

      refute Keyword.has_key?(request.query, :predefinedAcl)
      refute Map.has_key?(metadata_json(request), "acl")
    end

    test "a string ACL is sent as predefinedAcl verbatim", %{meta: meta} do
      {:ok, _} = CloudStorage.put(AclString, :original, meta)

      assert captured_request().query[:predefinedAcl] == "bucketOwnerRead"
    end

    test "a list ACL goes to the object resource's acl field", %{meta: meta} do
      {:ok, _} = CloudStorage.put(AclList, :original, meta)
      request = captured_request()

      refute Keyword.has_key?(request.query, :predefinedAcl)
      assert metadata_json(request)["acl"] == [%{"entity" => "allUsers", "role" => "READER"}]
    end

    test "an unknown ACL atom raises", %{meta: meta} do
      assert_raise ArgumentError, ~r/unsupported ACL :public_read_write/, fn ->
        CloudStorage.put(AclUnknown, :original, meta)
      end
    end

    test "gcs_optional_params/2 override the ACL-derived predefinedAcl", %{meta: meta} do
      {:ok, _} = CloudStorage.put(AclOverriddenByParams, :original, meta)
      query = captured_request().query

      assert query[:predefinedAcl] == "private"
      assert query[:userProject] == "p"
      assert Enum.count(query, fn {key, _} -> key == :predefinedAcl end) == 1
    end

    test "contentType is inferred from the filename when headers don't set it", %{meta: meta} do
      {:ok, _} = CloudStorage.put(AclDefault, :original, meta)

      assert metadata_json(captured_request())["contentType"] == "image/png"
    end

    test "string-keyed headers keep precedence over the inferred contentType", %{meta: meta} do
      {:ok, _} = CloudStorage.put(StringKeyHeaders, :original, meta)
      json = metadata_json(captured_request())

      assert json["contentType"] == "image/webp"
      assert Enum.count(json, fn {key, _} -> key == "contentType" end) == 1
    end

    test "errors raised inside gcs_object_headers/2 propagate", %{meta: meta} do
      assert_raise UndefinedFunctionError, fn ->
        CloudStorage.put(RaisingHeaders, :original, meta)
      end
    end

    test "errors raised inside gcs_optional_params/2 propagate", %{meta: meta} do
      assert_raise UndefinedFunctionError, fn ->
        CloudStorage.put(RaisingParams, :original, meta)
      end
    end

    test "definitions without the optional callbacks upload with defaults", %{meta: meta} do
      assert {:ok, %Object{name: "captured"}} = CloudStorage.put(AclDefault, :original, meta)

      assert captured_request().query == [uploadType: "multipart"]
    end
  end

  # ── Module API against real GCS ──────────────────────────────────────────

  describe "CloudStorage module API (real GCS)" do
    @describetag :integration

    setup do
      name = 8 |> :crypto.strong_rand_bytes() |> Base.encode16()

      wafile =
        @file_path
        |> Waffle.File.new(GCSTest.PublicUpload)
        |> Map.put(:file_name, "#{name}.png")

      %{name: name, meta: {wafile, nil}}
    end

    test "bucket/1 resolves a {:system, var} bucket from app config" do
      assert System.fetch_env!("WAFFLE_BUCKET") == CloudStorage.bucket(GCSTest.PublicUpload)
    end

    # These tests deliberately pin the full result shapes because they are
    # the contract consumers pattern-match on. Any change to them must show
    # up here as an explicit, versioned decision.

    @tag timeout: 15_000
    test "put/3 uploads a file and returns the GCS object", %{meta: meta, name: name} do
      assert {:ok, %Object{} = object} =
               CloudStorage.put(GCSTest.PublicUpload, :original, meta)

      assert object.name == "#{GCSTest.Run.storage_dir()}/#{name}.png"
    end

    @tag timeout: 15_000
    test "put/3 uploads binary data", %{name: name} do
      meta =
        {%Waffle.File{binary: File.read!(@file_path), file_name: "#{name}.png"}, nil}

      assert {:ok, %Object{}} =
               CloudStorage.put(GCSTest.PublicUpload, :original, meta)
    end

    @tag timeout: 15_000
    test "put/3 fails for an invalid bucket", %{meta: meta} do
      # 403, not 404: GCS does not disclose bucket existence on insert.
      assert {:error, %Error{status: 403, response: %{status: 403}}} =
               CloudStorage.put(GCSTest.InvalidBucket, :original, meta)
    end

    @tag timeout: 15_000
    test "delete/3 removes an existing object", %{meta: meta} do
      assert {:ok, _} = CloudStorage.put(GCSTest.PublicUpload, :original, meta)

      assert :ok = CloudStorage.delete(GCSTest.PublicUpload, :original, meta)
    end

    @tag timeout: 15_000
    test "delete/3 fails for a non-existent object or invalid bucket", %{meta: meta} do
      assert {:error, %Error{status: 404}} =
               CloudStorage.delete(GCSTest.PublicUpload, :original, meta)

      assert {:error, %Error{status: 404}} =
               CloudStorage.delete(GCSTest.InvalidBucket, :original, meta)
    end

    @tag timeout: 15_000
    test "url/3 returns a public URL pointing at the bucket and storage dir", %{
      meta: meta,
      name: name
    } do
      bucket = System.fetch_env!("WAFFLE_BUCKET")

      assert CloudStorage.url(GCSTest.PublicUpload, :original, meta) =~
               "/#{bucket}/#{GCSTest.Run.storage_dir()}/#{name}"
    end

    @tag timeout: 15_000
    test "url/3 returns a CDN URL without the bucket name in the path", %{
      meta: meta,
      name: name
    } do
      Application.put_env(:waffle, :asset_host, "cdn-domain.com")

      assert CloudStorage.url(GCSTest.PublicUpload, :original, meta) ==
               "https://cdn-domain.com/#{GCSTest.Run.storage_dir()}/#{name}.png"

      Application.delete_env(:waffle, :asset_host)
    end
  end
end
