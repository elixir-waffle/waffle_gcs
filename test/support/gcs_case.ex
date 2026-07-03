defmodule Waffle.GCSCase do
  @moduledoc """
  Shared case template for the real-GCS integration tests.

  `use Waffle.GCSCase` gives a test module:

    * the `:integration` and `:tmp_dir` module tags,
    * a `setup_all` that boots `:hackney` and points `:waffle` at `WAFFLE_BUCKET`,
    * a `setup` that copies a fixture image into the per-test `tmp_dir` and exposes
      `unique_basename`/`tmp_path` in the test context (and cleans the local file up),
    * the helper functions (`env_bucket/0`, `bucket_url/0,1`, `with_env/4`), and
    * the assertion macros (`assert_public/2`, `assert_private/2`, `assert_header/4`,
      `delete_and_assert_gone/2`, `assert_acls_public_reader/2`,
      `assert_public_with_extension/4`).

  These tests hit real Google Cloud Storage and require `WAFFLE_BUCKET` +
  `GCP_CREDENTIALS` to be set (and `WAFFLE_BUCKET2` for the bucket-from-scope test).
  """

  use ExUnit.CaseTemplate

  @img "test/support/image.png"

  using do
    quote do
      import Waffle.GCSCase
      alias Waffle.Storage.Google.CloudStorage

      @moduletag :integration
      @moduletag :tmp_dir
    end
  end

  setup_all do
    Application.ensure_all_started(:hackney)
    Application.put_env(:waffle, :virtual_host, true)
    Application.put_env(:waffle, :bucket, {:system, "WAFFLE_BUCKET"})
    :ok
  end

  setup meta do
    # Derive a stable, collision-free basename from ExUnit's per-test tmp_dir
    # (e.g. ".../tmp/MyTest/the_test_name") so concurrently-run test objects never
    # clash in the bucket.
    [_, unique_storage_dir] = :string.split(meta.tmp_dir, "/tmp/")
    [mod_str, test_str] = Path.split(unique_storage_dir)

    unique_basename = mod_str <> "__" <> test_str
    tmp_path = Path.join(meta.tmp_dir, unique_basename <> ".png")

    File.cp!(@img, tmp_path)
    on_exit(:cleanup_local_tmp, fn -> File.rm!(tmp_path) end)

    [unique_basename: unique_basename, tmp_path: tmp_path]
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  def env_bucket, do: System.fetch_env!("WAFFLE_BUCKET")

  def bucket_url(bucket \\ env_bucket()), do: "https://storage.googleapis.com/#{bucket}"

  @doc """
  The per-run storage directory all test definitions upload under
  (see `GCSTest.Run`). Use it in URL assertions instead of a literal prefix.
  """
  def storage_dir, do: GCSTest.Run.storage_dir()

  @doc """
  Temporarily set `Application` env for the duration of `fun`, restoring the
  previous value (or deleting the key if it was unset) afterwards.
  """
  def with_env(app, key, value, fun) do
    previous = Application.get_env(app, key, :_unset)
    Application.put_env(app, key, value)

    try do
      fun.()
    after
      case previous do
        :_unset -> Application.delete_env(app, key)
        _ -> Application.put_env(app, key, previous)
      end
    end
  end

  # ── Assertion macros ─────────────────────────────────────────────────────

  defmacro assert_public(definition, args) do
    quote bind_quoted: [definition: definition, args: args] do
      url = definition.url(args)
      {:ok, {{_, code, _}, _, _}} = :httpc.request(to_charlist(url))
      assert code == 200
    end
  end

  defmacro assert_private(definition, args) do
    quote bind_quoted: [definition: definition, args: args] do
      unsigned_url = definition.url(args)
      {:ok, {{_, code, _}, _, _}} = :httpc.request(to_charlist(unsigned_url))
      assert code == 403

      signed_url = definition.url(args, signed: true)
      {:ok, {{_, code, _}, _, _}} = :httpc.request(to_charlist(signed_url))
      assert code == 200
    end
  end

  defmacro assert_header(definition, args, header, expected) do
    quote bind_quoted: [definition: definition, args: args, header: header, expected: expected] do
      url = definition.url(args)
      {:ok, {{_, 200, _}, headers, _}} = :httpc.request(to_charlist(url))
      char_header = to_charlist(header)

      actual =
        Enum.find_value(headers, fn
          {^char_header, value} -> value
          _ -> nil
        end)

      assert to_charlist(expected) == actual
    end
  end

  defmacro assert_public_with_extension(definition, args, version, extension) do
    quote bind_quoted: [
            definition: definition,
            args: args,
            version: version,
            extension: extension
          ] do
      url = definition.url(args, version)
      {:ok, {{_, code, _}, _, _}} = :httpc.request(to_charlist(url))
      assert code == 200
      assert Path.extname(url) == extension
    end
  end

  defmacro assert_acls_public_reader(definition, args) do
    quote bind_quoted: [definition: definition, args: args] do
      alias Waffle.Storage.Google.CloudStorage

      {:ok, %GoogleApi.Storage.V1.Model.ObjectAccessControls{} = acls} =
        GoogleApi.Storage.V1.Api.ObjectAccessControls.storage_object_access_controls_list(
          CloudStorage.conn(),
          CloudStorage.bucket(definition),
          "#{GCSTest.Run.storage_dir()}/#{args}"
        )

      assert [
               %{role: "OWNER", entity: service_account},
               %{role: "READER", entity: "allUsers"}
             ] = acls.items |> Enum.sort_by(& &1.role)

      assert service_account =~ ".iam.gserviceaccount.com"
    end
  end

  defmacro delete_and_assert_gone(definition, args) do
    quote bind_quoted: [definition: definition, args: args] do
      :ok = definition.delete(args)
      signed_url = definition.url(args, signed: true)
      {:ok, {{_, code, _}, _, _}} = :httpc.request(to_charlist(signed_url))

      # If buckets aren't configured to be public at the bucket level, deleted
      # objects may return 403 Forbidden instead of 404 Not Found, even with a
      # signed URL.
      assert code in [403, 404]
    end
  end
end
