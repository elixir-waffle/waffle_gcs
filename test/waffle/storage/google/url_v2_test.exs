defmodule Waffle.Storage.Google.UrlV2Test do
  # async: false — the endpoint tests mutate :waffle app env, and the signing
  # tests swap the (global) legacy Goth.Config identity.
  use ExUnit.Case, async: false

  alias Waffle.Storage.Google.UrlV2

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

  describe "endpoint/1" do
    test "returns the option value when provided" do
      assert "test.com" == UrlV2.endpoint(asset_host: "test.com")
    end

    test "returns the application config as a back-up" do
      Application.put_env(:waffle, :asset_host, "test.com")
      result = UrlV2.endpoint()
      Application.delete_env(:waffle, :asset_host)

      assert "test.com" == result
    end

    test "returns default endpoint" do
      assert "storage.googleapis.com" == UrlV2.endpoint()
    end
  end

  describe "build/4 with signed: true" do
    # Deterministic and offline: a throwaway RSA key stands in for the
    # service account, and the signature is verified cryptographically
    # against the reconstructed canonical request — so signing internals
    # (key loading, encoding, URL assembly) can change without a live-GCS
    # run proving them again.

    @client_email "url-v2-signing-test@example.iam.gserviceaccount.com"
    @bucket "signing-test-bucket"

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
        Waffle.GCSCase.with_env(:waffle, :bucket, @bucket, fn ->
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

    test "tampered canonical request does not verify", ctx do
      meta = {%Waffle.File{file_name: "image.png"}, nil}

      url =
        Waffle.GCSCase.with_env(:waffle, :bucket, @bucket, fn ->
          UrlV2.build(GCSTest.PublicUpload, :original, meta, signed: true)
        end)

      %URI{path: path, query: query} = URI.parse(url)
      q = URI.decode_query(query)
      signature = Base.decode64!(q["Signature"])

      tampered = "GET\n\n\n#{q["Expires"]}\n#{path}x"
      refute :public_key.verify(tampered, :sha256, signature, ctx.public_key)
    end
  end

  defp stop_goth_config do
    Supervisor.terminate_child(Goth.Supervisor, Goth.Config)
    Supervisor.delete_child(Goth.Supervisor, Goth.Config)
    :ok
  end
end
