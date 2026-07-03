defmodule Waffle.Integration.GCSFeaturesTest do
  # Canonical public-API integration suite. Each test exercises one Waffle feature
  # through `definition.store/url/delete` against real GCS, using the single-purpose
  # definitions in `test/support/feature_definitions.ex`. Shared setup, helpers, and
  # assertion macros live in `Waffle.GCSCase`.
  use Waffle.GCSCase

  @img "test/support/image.png"
  @img_with_space "test/support/image two.png"
  @img_with_plus "test/support/image+three.png"

  # ── Public uploads ─────────────────────────────────────────────────────

  describe "public uploads" do
    @tag timeout: 15_000
    test "stores a file and serves it at an unsigned URL", meta do
      assert {:ok, name} = GCSTest.PublicUpload.store(meta.tmp_path)
      assert name == meta.unique_basename <> ".png"
      assert_public(GCSTest.PublicUpload, name)
      assert_acls_public_reader(GCSTest.PublicUpload, name)
      delete_and_assert_gone(GCSTest.PublicUpload, name)
    end
  end

  # ── Private uploads ────────────────────────────────────────────────────

  describe "private uploads" do
    @tag timeout: 15_000
    test "rejects unsigned access and allows signed access", meta do
      assert {:ok, name} = GCSTest.PrivateUpload.store(meta.tmp_path)
      assert name == meta.unique_basename <> ".png"
      assert_private(GCSTest.PrivateUpload, name)
      delete_and_assert_gone(GCSTest.PrivateUpload, name)
    end
  end

  # ── GCS object headers ────────────────────────────────────────────────

  describe "GCS object headers" do
    @tag timeout: 15_000
    test "sets custom content-type on the uploaded object", meta do
      assert {:ok, name} = GCSTest.WithContentType.store(meta.tmp_path)
      assert name == meta.unique_basename <> ".png"
      assert_acls_public_reader(GCSTest.WithContentType, name)
      assert_header(GCSTest.WithContentType, name, "content-type", "image/gif")
      delete_and_assert_gone(GCSTest.WithContentType, name)
    end

    @tag timeout: 15_000
    test "sets custom content-disposition on the uploaded object", meta do
      assert {:ok, name} = GCSTest.WithContentDisposition.store(meta.tmp_path)
      assert name == meta.unique_basename <> ".png"
      assert_acls_public_reader(GCSTest.WithContentDisposition, name)

      assert_header(
        GCSTest.WithContentDisposition,
        name,
        "content-disposition",
        "attachment; filename=\"abc.png\""
      )

      delete_and_assert_gone(GCSTest.WithContentDisposition, name)
    end
  end

  # ── Binary uploads ────────────────────────────────────────────────────

  describe "binary uploads" do
    @tag timeout: 15_000
    test "uploads from in-memory binary data", meta do
      binary = File.read!(meta.tmp_path)
      filename = meta.unique_basename <> ".png"
      assert {:ok, name} = GCSTest.PublicUpload.store(%{filename: filename, binary: binary})
      assert_public(GCSTest.PublicUpload, name)
      delete_and_assert_gone(GCSTest.PublicUpload, name)
    end
  end

  # ── Custom filenames ───────────────────────────────────────────────────

  describe "custom filenames" do
    @tag timeout: 15_000
    test "URL reflects the custom filename pattern with scope", meta do
      scope = %{id: 1}
      assert {:ok, name} = GCSTest.WithCustomFilename.store({meta.tmp_path, scope})

      url = GCSTest.WithCustomFilename.url({name, scope})
      assert url == "#{bucket_url()}/#{storage_dir()}/1_#{meta.unique_basename}.png"

      assert_public(GCSTest.WithCustomFilename, {name, scope})
      delete_and_assert_gone(GCSTest.WithCustomFilename, {name, scope})
    end

    @tag timeout: 150_000
    test "multi-version filename includes version in each URL", meta do
      mod = GCSTest.WithMultiVersionFilename
      scope = %{id: 1}
      assert {:ok, name} = mod.store({meta.tmp_path, scope})
      assert name == meta.unique_basename <> ".png"

      assert mod.url({name, scope}, :original) ==
               "#{bucket_url()}/#{storage_dir()}/1_original_#{name}"

      assert mod.url({name, scope}, :thumb) ==
               "#{bucket_url()}/#{storage_dir()}/1_thumb_#{name}"

      # Default version (no arg) resolves to :original
      assert mod.url({name, scope}) ==
               "#{bucket_url()}/#{storage_dir()}/1_original_#{name}"

      # Both versions are actually accessible, and (no transform) keep the .png extension
      assert_public_with_extension(mod, {name, scope}, :original, ".png")
      assert_public_with_extension(mod, {name, scope}, :thumb, ".png")

      delete_and_assert_gone(mod, {name, scope})
    end
  end

  # ── Scoped storage directories ─────────────────────────────────────────

  describe "scoped storage directories" do
    @tag timeout: 15_000
    test "URL path includes the scoped directory", meta do
      scope = %{id: 42}
      assert {:ok, name} = GCSTest.WithScopedDir.store({meta.tmp_path, scope})

      url = GCSTest.WithScopedDir.url({name, scope})
      assert url == "#{bucket_url()}/#{storage_dir()}/scoped/42/#{name}"

      assert_public(GCSTest.WithScopedDir, {name, scope})
      assert_acls_public_reader(GCSTest.WithScopedDir, "scoped/42/#{name}")
      delete_and_assert_gone(GCSTest.WithScopedDir, {name, scope})
    end
  end

  # ── Versions and transforms ───────────────────────────────────────────

  describe "versions and transforms" do
    @tag timeout: 150_000
    test "creates a transformed thumbnail alongside the original", meta do
      assert {:ok, name} = GCSTest.WithVersions.store(meta.tmp_path)

      # Original is accessible
      assert_public(GCSTest.WithVersions, name)

      # Thumbnail is accessible and was converted to .jpg
      assert_public_with_extension(GCSTest.WithVersions, name, :thumb, ".jpg")

      delete_and_assert_gone(GCSTest.WithVersions, name)
    end

    test "returns nil URL for a skipped version" do
      assert nil == GCSTest.WithSkippedVersion.url("image.png")
    end
  end

  # ── URL generation ────────────────────────────────────────────────────

  describe "URL generation" do
    test "default URL includes bucket and storage directory" do
      url = GCSTest.PublicUpload.url("image.png")
      assert url == "#{bucket_url()}/#{storage_dir()}/image.png"
    end

    @tag skip:
           "GCS URL builder reads asset_host from app config, not definition.asset_host/0 — unlike S3/Local adapters"
    @tag upstream_mismatch: "UrlV2 should call definition.asset_host/0 like S3/Local adapters do"
    test "definition-level asset_host replaces the default endpoint" do
      url = GCSTest.WithAssetHost.url("image.png")
      assert url == "https://cdn.example.com/#{storage_dir()}/image.png"
    end

    test "app-level asset_host overrides the default endpoint" do
      with_env(:waffle, :asset_host, "app-cdn.example.com", fn ->
        url = GCSTest.PublicUpload.url("image.png")
        assert url == "https://app-cdn.example.com/#{storage_dir()}/image.png"
      end)
    end

    @tag skip: "TODO - determine if this is relevant to GCS"
    test "app-level asset_host via {:system, env_var} tuple" do
      custom_asset_host = "https://some.cloudfront.com"

      with_env(:waffle, :asset_host, {:system, "WAFFLE_ASSET_HOST"}, fn ->
        System.put_env("WAFFLE_ASSET_HOST", custom_asset_host)

        assert "#{custom_asset_host}/#{storage_dir()}/image.png" ==
                 GCSTest.PublicUpload.url(@img)
      end)
    end

    @tag skip: "TODO - determine if this is relevant to GCS"
    test "asset_host: false reverts to default GCS endpoint" do
      with_env(:waffle, :asset_host, false, fn ->
        assert "#{bucket_url()}/#{storage_dir()}/image.png" == GCSTest.PublicUpload.url(@img)
      end)
    end

    test "URL-encodes filenames with spaces" do
      url = GCSTest.PublicUpload.url(@img_with_space)
      assert url == "#{bucket_url()}/#{storage_dir()}/image%20two.png"
    end

    @tag skip: "TODO - determine if this is relevant to GCS"
    test "URL-encodes filenames with plus signs" do
      url = GCSTest.PublicUpload.url(@img_with_plus)
      assert url == "#{bucket_url()}/#{storage_dir()}/image%2Bthree.png"
    end

    test "signed URLs include signature query parameters" do
      url = GCSTest.PublicUpload.url("image.png", signed: true)
      assert url =~ "GoogleAccessId="
      assert url =~ "Signature="
    end
  end

  # ── Bucket configuration ──────────────────────────────────────────────

  describe "bucket configuration" do
    @tag timeout: 15_000
    test "definition can specify its own bucket", meta do
      # URL is computed from the definition's bucket before anything is stored.
      expected_url = "#{bucket_url()}/#{storage_dir()}/#{meta.unique_basename}.png"
      assert GCSTest.WithBucket.url(meta.tmp_path) == expected_url

      assert {:ok, name} = GCSTest.WithBucket.store(meta.tmp_path)
      assert name == meta.unique_basename <> ".png"
      delete_and_assert_gone(GCSTest.WithBucket, name)
    end

    @tag timeout: 15_000
    test "store returns error for a definition with an invalid bucket", meta do
      assert {:error, _} = GCSTest.InvalidBucket.store(meta.tmp_path)
    end

    @tag timeout: 15_000
    test "store returns error when app-level bucket is invalid" do
      with_env(:waffle, :bucket, "unknown-bucket", fn ->
        assert {:error, _} = GCSTest.PublicUpload.store(@img)
      end)
    end

    @tag upstream_mismatch: "This is a bug w/ bucket/1 not being implemented. To be resolved"
    @tag :bucket_with_file_and_scope
    @tag timeout: 150_000
    test "bucket/1 selects bucket from scope" do
      mod = GCSTest.WithBucketInScope

      bucket = System.fetch_env!("WAFFLE_BUCKET2")
      scope = %{id: 1, bucket: bucket}
      assert {:ok, name} = mod.store({@img, scope})

      assert mod.url({name, scope}) ==
               "#{bucket_url(bucket)}/#{storage_dir()}/image.png"

      assert_public(mod, {name, scope})
      delete_and_assert_gone(mod, {name, scope})
    end
  end

  # ── Delete ─────────────────────────────────────────────────────────────

  describe "delete" do
    @tag timeout: 15_000
    test "removes the file from GCS and subsequent access returns 403/404", meta do
      assert {:ok, name} = GCSTest.PublicUpload.store(meta.tmp_path)
      assert_public(GCSTest.PublicUpload, name)

      assert :ok = GCSTest.PublicUpload.delete(name)

      signed_url = GCSTest.PublicUpload.url(name, signed: true)
      {:ok, {{_, code, _}, _, _}} = :httpc.request(to_charlist(signed_url))
      assert code in [403, 404]
    end

    # Waffle's definition.delete/1 always returns :ok (discards storage errors),
    # so these tests go through CloudStorage.delete/3 directly.
    @tag timeout: 15_000
    test "CloudStorage.delete/3 returns error for non-existent object" do
      file = %{file_name: "nonexistent.png"}
      assert {:error, _} = CloudStorage.delete(GCSTest.PublicUpload, :original, {file, nil})
    end

    @tag timeout: 15_000
    test "CloudStorage.delete/3 returns error for invalid bucket" do
      file = %{file_name: "anything.png"}
      assert {:error, _} = CloudStorage.delete(GCSTest.InvalidBucket, :original, {file, nil})
    end
  end
end
