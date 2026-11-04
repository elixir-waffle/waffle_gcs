defmodule Waffle.Storage.Google.UrlV2Test do
  # async: false — the endpoint tests mutate :waffle app env, and the signing
  # tests swap the (global) legacy Goth.Config identity.
  use ExUnit.Case, async: false

  import Waffle.GCSCase, only: [with_env: 4]

  alias Waffle.Storage.Google.UrlV2

  @bucket "url-v2-test-bucket"

  describe "expiry/1" do
    test "returns a default value when option is not found" do
      assert 3600 == UrlV2.expiry()
    end

    test "uses value from keyword list" do
      assert 100 == UrlV2.expiry(expires_in: 100)
    end

    test "respects minimum and maximum values" do
      assert 1 == UrlV2.expiry(expires_in: -100)
      assert 604_800 == UrlV2.expiry(expires_in: 9_999_999_999)
    end
  end

  describe "signed?/1" do
    test "returns the option value when found" do
      assert UrlV2.signed?(signed: true)
    end

    test "returns false as the default" do
      assert false == UrlV2.signed?()
    end
  end

  describe "asset_host/2" do
    test "per-call option wins over the definition callback and app config" do
      with_env(:waffle, :asset_host, "app-cdn.example.com", fn ->
        assert "call-cdn.example.com" ==
                 UrlV2.asset_host(GCSTest.WithAssetHost, asset_host: "call-cdn.example.com")
      end)
    end

    test "definition callback wins over app config" do
      with_env(:waffle, :asset_host, "app-cdn.example.com", fn ->
        assert "cdn.example.com" == UrlV2.asset_host(GCSTest.WithAssetHost)
      end)
    end

    test "app config is read through the definition's default callback" do
      with_env(:waffle, :asset_host, "app-cdn.example.com", fn ->
        assert "app-cdn.example.com" == UrlV2.asset_host(GCSTest.PublicUpload)
      end)
    end

    test "resolves {:system, var} from the environment" do
      System.put_env("WAFFLE_TEST_ASSET_HOST", "https://env-cdn.example.com")
      on_exit(fn -> System.delete_env("WAFFLE_TEST_ASSET_HOST") end)

      assert "https://env-cdn.example.com" ==
               UrlV2.asset_host(GCSTest.PublicUpload,
                 asset_host: {:system, "WAFFLE_TEST_ASSET_HOST"}
               )

      with_env(:waffle, :asset_host, {:system, "WAFFLE_TEST_ASSET_HOST"}, fn ->
        assert "https://env-cdn.example.com" == UrlV2.asset_host(GCSTest.PublicUpload)
      end)
    end

    test "an unset {:system, var} selects the GCS endpoint" do
      System.delete_env("WAFFLE_TEST_ASSET_HOST")

      assert nil ==
               UrlV2.asset_host(GCSTest.PublicUpload,
                 asset_host: {:system, "WAFFLE_TEST_ASSET_HOST"}
               )
    end

    test "false selects the GCS endpoint, per call and from config" do
      assert nil == UrlV2.asset_host(GCSTest.WithAssetHost, asset_host: false)

      with_env(:waffle, :asset_host, false, fn ->
        assert nil == UrlV2.asset_host(GCSTest.PublicUpload)
      end)
    end

    test "a nil per-call option falls through to the definition" do
      assert "cdn.example.com" == UrlV2.asset_host(GCSTest.WithAssetHost, asset_host: nil)
    end

    test "is nil when nothing is configured" do
      assert nil == UrlV2.asset_host(GCSTest.PublicUpload)
    end
  end

  describe "build/4 with an asset host" do
    test "serves the object path from the asset host without the bucket" do
      assert "https://call-cdn.example.com/#{GCSTest.Run.storage_dir()}/image.png" ==
               public_url("image.png", asset_host: "call-cdn.example.com")
    end

    test "keeps the scheme of a URL-shaped asset host and trims a trailing slash" do
      assert "http://localhost:4000/files/#{GCSTest.Run.storage_dir()}/image.png" ==
               public_url("image.png", asset_host: "http://localhost:4000/files/")
    end

    test "false serves from the GCS endpoint with the bucket" do
      assert "https://storage.googleapis.com/#{@bucket}/#{GCSTest.Run.storage_dir()}/image.png" ==
               public_url("image.png", asset_host: false)
    end
  end

  describe "build/4 path encoding" do
    test "keeps / separators and encodes everything else per segment" do
      assert public_url("report#final?.png") ==
               "https://storage.googleapis.com/#{@bucket}/#{GCSTest.Run.storage_dir()}/report%23final%3F.png"
    end

    test "encodes +, %, and spaces" do
      assert public_url("a+b 100%.png") ==
               "https://storage.googleapis.com/#{@bucket}/#{GCSTest.Run.storage_dir()}/a%2Bb%20100%25.png"
    end

    test "round-trips through URI.parse to the original object name" do
      %URI{path: path, query: nil, fragment: nil} = URI.parse(public_url("report#final?.png"))

      assert URI.decode(path) == "/#{@bucket}/#{GCSTest.Run.storage_dir()}/report#final?.png"
    end
  end

  describe "build/4 with signed: true" do
    # Deterministic and offline: a throwaway RSA key stands in for the
    # service account, and the signature is verified cryptographically
    # against the reconstructed canonical request — so signing internals
    # (key loading, encoding, URL assembly) can change without a live-GCS
    # run proving them again.

    # The identity swap below needs goth >= 1.3's lazily-started legacy
    # Goth.Config (goth < 1.3 freezes the app-boot config into the child
    # spec); test_helper.exs excludes the tag on old-goth blend runs.
    @describetag :goth_config_swap

    @client_email "url-v2-signing-test@example.iam.gserviceaccount.com"

    setup do
      key = :public_key.generate_key({:rsa, 2048, 65_537})
      pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])

      dummy_service_account =
        Jason.encode!(%{
          "type" => "service_account",
          "project_id" => "signing-test",
          "private_key_id" => "0",
          "private_key" => pem,
          "client_email" => @client_email,
          "client_id" => "0",
          "token_uri" => "https://oauth2.googleapis.com/token"
        })

      prev_json = Application.get_env(:goth, :json, :unset)

      # Goth.Config starts lazily on first use and loads from :goth app env:
      # restart it against the throwaway identity, and leave a fresh lazy
      # start against the prior config for whatever runs next.
      stop_goth_config()
      Application.put_env(:goth, :json, dummy_service_account)

      on_exit(fn ->
        case prev_json do
          :unset -> Application.delete_env(:goth, :json)
          prev -> Application.put_env(:goth, :json, prev)
        end

        stop_goth_config()
      end)

      # {:RSAPrivateKey, _version, modulus, public_exponent, ...}
      public_key = {:RSAPublicKey, elem(key, 2), elem(key, 3)}

      %{public_key: public_key}
    end

    test "signed URL carries a valid RSA-SHA256 signature over the canonical request", ctx do
      meta = {%Waffle.File{file_name: "sig test.png"}, nil}

      url =
        with_env(:waffle, :bucket, @bucket, fn ->
          UrlV2.build(GCSTest.PublicUpload, :original, meta, signed: true, expires_in: 1234)
        end)

      now = System.os_time(:second)

      assert %URI{scheme: "https", host: "storage.googleapis.com", path: path, query: query} =
               URI.parse(url)

      # The signed resource is /<bucket>/<url-encoded object path>
      assert path == "/#{@bucket}/#{GCSTest.Run.storage_dir()}/sig%20test.png"

      q = URI.decode_query(query)
      assert q["GoogleAccessId"] == @client_email

      expires = String.to_integer(q["Expires"])
      assert expires > now
      assert expires <= now + 1234

      # v2 canonical request: METHOD \n MD5 \n CONTENT-TYPE \n EXPIRES \n RESOURCE
      canonical = "GET\n\n\n#{q["Expires"]}\n#{path}"
      signature = Base.decode64!(q["Signature"])

      assert :public_key.verify(canonical, :sha256, signature, ctx.public_key)
    end

    test "signs the percent-encoded resource for reserved characters", ctx do
      meta = {%Waffle.File{file_name: "v#2+100%?.png"}, nil}

      url =
        with_env(:waffle, :bucket, @bucket, fn ->
          UrlV2.build(GCSTest.PublicUpload, :original, meta, signed: true)
        end)

      assert %URI{path: path, query: query, fragment: nil} = URI.parse(url)
      assert path == "/#{@bucket}/#{GCSTest.Run.storage_dir()}/v%232%2B100%25%3F.png"

      q = URI.decode_query(query)
      canonical = "GET\n\n\n#{q["Expires"]}\n#{path}"
      signature = Base.decode64!(q["Signature"])

      assert :public_key.verify(canonical, :sha256, signature, ctx.public_key)
    end

    test "ignores the asset host, signs the GCS resource, and warns", ctx do
      meta = {%Waffle.File{file_name: "image.png"}, nil}

      {url, log} =
        with_env(:waffle, :bucket, @bucket, fn ->
          ExUnit.CaptureLog.with_log(fn ->
            UrlV2.build(GCSTest.WithAssetHost, :original, meta, signed: true)
          end)
        end)

      assert log =~ ~s(ignoring asset_host "cdn.example.com")

      assert %URI{host: "storage.googleapis.com", path: path, query: query} = URI.parse(url)
      assert path == "/#{@bucket}/#{GCSTest.Run.storage_dir()}/image.png"

      q = URI.decode_query(query)
      canonical = "GET\n\n\n#{q["Expires"]}\n#{path}"
      signature = Base.decode64!(q["Signature"])

      assert :public_key.verify(canonical, :sha256, signature, ctx.public_key)
    end

    test "tampered canonical request does not verify", ctx do
      meta = {%Waffle.File{file_name: "image.png"}, nil}

      url =
        with_env(:waffle, :bucket, @bucket, fn ->
          UrlV2.build(GCSTest.PublicUpload, :original, meta, signed: true)
        end)

      %URI{path: path, query: query} = URI.parse(url)
      q = URI.decode_query(query)
      signature = Base.decode64!(q["Signature"])

      tampered = "GET\n\n\n#{q["Expires"]}\n#{path}x"
      refute :public_key.verify(tampered, :sha256, signature, ctx.public_key)
    end
  end

  defp public_url(file_name, options \\ []) do
    meta = {%Waffle.File{file_name: file_name}, nil}

    with_env(:waffle, :bucket, @bucket, fn ->
      UrlV2.build(GCSTest.PublicUpload, :original, meta, options)
    end)
  end

  defp stop_goth_config do
    Supervisor.terminate_child(Goth.Supervisor, Goth.Config)
    Supervisor.delete_child(Goth.Supervisor, Goth.Config)
    :ok
  end
end
