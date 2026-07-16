defmodule Waffle.Storage.Google.CloudStorageTest do
  # Tests the `CloudStorage` module's API directly (as opposed to the public
  # `definition.store/url/delete` flow, which is covered by the integration suite
  # under test/integration/). Path/name construction is exercised as pure unit
  # tests; the put/delete/url round-trips are tagged `:integration` (real GCS).
  use ExUnit.Case, async: false

  alias Waffle.Storage.Google.CloudStorage

  @file_path "test/support/image.png"

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

    # These tests deliberately pin the full result shapes — dependency structs
    # included — because they are the contract consumers pattern-match on
    # today. Any change to them (including wrapping in library-owned types)
    # must show up here as an explicit, versioned decision.

    @tag timeout: 15_000
    test "put/3 uploads a file and returns the GCS object", %{meta: meta, name: name} do
      assert {:ok, %GoogleApi.Storage.V1.Model.Object{} = object} =
               CloudStorage.put(GCSTest.PublicUpload, :original, meta)

      assert object.name == "#{GCSTest.Run.storage_dir()}/#{name}.png"
    end

    @tag timeout: 15_000
    test "put/3 uploads binary data", %{name: name} do
      meta =
        {%Waffle.File{binary: File.read!(@file_path), file_name: "#{name}.png"}, nil}

      assert {:ok, %GoogleApi.Storage.V1.Model.Object{}} =
               CloudStorage.put(GCSTest.PublicUpload, :original, meta)
    end

    @tag timeout: 15_000
    test "put/3 fails for an invalid bucket", %{meta: meta} do
      # 403, not 404: GCS does not disclose bucket existence on insert.
      assert {:error, %Tesla.Env{status: 403}} =
               CloudStorage.put(GCSTest.InvalidBucket, :original, meta)
    end

    @tag timeout: 15_000
    test "delete/3 removes an existing object", %{meta: meta} do
      assert {:ok, _} = CloudStorage.put(GCSTest.PublicUpload, :original, meta)

      assert {:ok, %Tesla.Env{status: 204}} =
               CloudStorage.delete(GCSTest.PublicUpload, :original, meta)
    end

    @tag timeout: 15_000
    test "delete/3 fails for a non-existent object or invalid bucket", %{meta: meta} do
      assert {:error, %Tesla.Env{status: 404}} =
               CloudStorage.delete(GCSTest.PublicUpload, :original, meta)

      assert {:error, %Tesla.Env{status: 404}} =
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
