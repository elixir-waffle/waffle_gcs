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
    # Today every upload without an explicit contentType header is stored as
    # application/octet-stream — browsers download images instead of showing
    # them. The S3 adapter infers MIME type from the filename; this asserts
    # that intended behavior.
    @tag :pending_content_type_inference
    @tag upstream_mismatch: "S3 adapter infers MIME from the filename; GCS stores octet-stream"
    @tag timeout: 15_000
    test "infers content-type from the file extension when no header is set", meta do
      assert {:ok, name} = GCSTest.PublicUpload.store(meta.tmp_path)
      assert_header(GCSTest.PublicUpload, name, "content-type", "image/png")
      delete_and_assert_gone(GCSTest.PublicUpload, name)
    end

    @tag timeout: 15_000
    test "sets custom content-type from a keyword list of headers", meta do
      assert {:ok, name} = GCSTest.WithKeywordHeaders.store(meta.tmp_path)
      assert_header(GCSTest.WithKeywordHeaders, name, "content-type", "image/gif")
      delete_and_assert_gone(GCSTest.WithKeywordHeaders, name)
    end

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

  # ── GCS optional params ───────────────────────────────────────────────

  describe "GCS optional params" do
    @tag timeout: 15_000
    test "gcs_optional_params/2 values reach the API (predefinedAcl)", meta do
      assert {:ok, name} = GCSTest.WithOptionalParams.store(meta.tmp_path)

      # The definition sets no ACL of its own, so public readability can only
      # have come from the predefinedAcl query param.
      assert_public(GCSTest.WithOptionalParams, name)
      delete_and_assert_gone(GCSTest.WithOptionalParams, name)
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

      # delete/1 removes every version, not just the default one
      :ok = GCSTest.WithVersions.delete(name)
      assert_version_gone(GCSTest.WithVersions, name, :original)
      assert_version_gone(GCSTest.WithVersions, name, :thumb)
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

    @tag :pending_asset_host
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

    @tag :pending_asset_host
    @tag upstream_mismatch: "S3/Local support {:system, var} asset_host values (with scheme)"
    test "app-level asset_host via {:system, env_var} tuple" do
      custom_asset_host = "https://some.cloudfront.com"

      with_env(:waffle, :asset_host, {:system, "WAFFLE_ASSET_HOST"}, fn ->
        System.put_env("WAFFLE_ASSET_HOST", custom_asset_host)

        assert "#{custom_asset_host}/#{storage_dir()}/image.png" ==
                 GCSTest.PublicUpload.url(@img)
      end)
    end

    @tag :pending_asset_host
    @tag upstream_mismatch: "S3/Local treat asset_host: false as 'use the default endpoint'"
    test "asset_host: false reverts to default GCS endpoint" do
      with_env(:waffle, :asset_host, false, fn ->
        assert "#{bucket_url()}/#{storage_dir()}/image.png" == GCSTest.PublicUpload.url(@img)
      end)
    end

    test "URL-encodes filenames with spaces" do
      url = GCSTest.PublicUpload.url(@img_with_space)
      assert url == "#{bucket_url()}/#{storage_dir()}/image%20two.png"
    end

    # NOTE: an unencoded "+" is legal in a URL *path* segment, so %2B here is
    # S3-adapter parity, not a GCS requirement — the URL-encoding fix should
    # decide this deliberately.
    @tag :pending_url_encoding
    @tag upstream_mismatch: "S3 adapter percent-encodes '+' in object paths"
    test "URL-encodes filenames with plus signs" do
      url = GCSTest.PublicUpload.url(@img_with_plus)
      assert url == "#{bucket_url()}/#{storage_dir()}/image%2Bthree.png"
    end

    test "signed URLs include signature query parameters" do
      url = GCSTest.PublicUpload.url("image.png", signed: true)
      assert url =~ "GoogleAccessId="
      assert url =~ "Signature="
    end

    # GCS validates a v2 signature against the canonical resource
    # "/<bucket>/<object>". With an asset_host configured, the URL builder
    # drops the bucket segment, so the signer signs "/<object>" — a resource
    # GCS will never agree with. The URL looks fine and returns 403 forever.
    # Until the fix decides between signing the real GCS resource or refusing
    # the combination, this test only pins the current output shape so a
    # refactor can't change it unnoticed.
    @tag upstream_mismatch:
           "signs '/<object>' instead of '/<bucket>/<object>' when asset_host is set"
    test "signed URL with asset_host is well-formed but its signature cannot validate" do
      with_env(:waffle, :asset_host, "app-cdn.example.com", fn ->
        url = GCSTest.PublicUpload.url("image.png", signed: true)

        assert url =~ "https://app-cdn.example.com/#{storage_dir()}/image.png"
        assert url =~ "Signature="
      end)
    end
  end

  # ── Special-character filenames ──────────────────────────────────────
  #
  # Each test stages the fixture under a hostile name and round-trips it:
  # store -> GET via the generated URL -> delete. These pin URL encoding
  # behavior end-to-end, not just the generated URL string.

  describe "special-character filenames" do
    @tag timeout: 15_000
    test "round-trips a filename containing spaces", meta do
      path = stage_fixture(meta, "#{meta.unique_basename} with space.png")

      assert {:ok, name} = GCSTest.PublicUpload.store(path)
      assert name == "#{meta.unique_basename} with space.png"
      assert_public(GCSTest.PublicUpload, name)

      # Signed URLs must survive the percent-encoded path too: the signature
      # is computed over the encoded resource.
      signed_url = GCSTest.PublicUpload.url(name, signed: true)
      {:ok, {{_, code, _}, _, _}} = :httpc.request(to_charlist(signed_url))
      assert code == 200

      delete_and_assert_gone(GCSTest.PublicUpload, name)
    end

    @tag timeout: 15_000
    test "round-trips a filename containing unicode", meta do
      path = stage_fixture(meta, "#{meta.unique_basename}_ünïcode_日本.png")

      assert {:ok, name} = GCSTest.PublicUpload.store(path)
      assert_public(GCSTest.PublicUpload, name)
      delete_and_assert_gone(GCSTest.PublicUpload, name)
    end

    @tag timeout: 15_000
    test "round-trips a filename containing a percent sign", meta do
      path = stage_fixture(meta, "#{meta.unique_basename}_100%.png")

      assert {:ok, name} = GCSTest.PublicUpload.store(path)
      assert_public(GCSTest.PublicUpload, name)
      delete_and_assert_gone(GCSTest.PublicUpload, name)
    end

    @tag :pending_url_encoding
    @tag upstream_mismatch:
           "URI.encode/1 leaves # unencoded, so the URL truncates at the fragment"
    @tag timeout: 15_000
    test "round-trips a filename containing a hash", meta do
      path = stage_fixture(meta, "#{meta.unique_basename}_v#2.png")

      assert {:ok, name} = GCSTest.PublicUpload.store(path)
      assert_public(GCSTest.PublicUpload, name)
      delete_and_assert_gone(GCSTest.PublicUpload, name)
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
