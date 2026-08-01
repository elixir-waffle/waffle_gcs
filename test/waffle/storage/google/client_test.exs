defmodule Waffle.Storage.Google.ClientTest do
  use ExUnit.Case, async: false

  alias Waffle.Storage.Google.{Client, Error, Object}
  alias Waffle.Storage.Google.Client.{Request, Response}

  doctest Waffle.Storage.Google.Util

  defmodule StubFetcher do
    @behaviour Waffle.Storage.Google.Token.Fetcher
    @impl true
    def get_token(_scope), do: "stub-token"
  end

  defmodule StubTransport do
    @behaviour Waffle.Storage.Google.Transport

    @impl true
    def execute(request, opts) do
      send(self(), {:request, request})
      Keyword.fetch!(opts, :respond).(request)
    end
  end

  @opts [transport: StubTransport]

  setup do
    original = Application.fetch_env!(:waffle, :token_fetcher)
    Application.put_env(:waffle, :token_fetcher, StubFetcher)
    on_exit(fn -> Application.put_env(:waffle, :token_fetcher, original) end)
  end

  defp respond(status, body, headers \\ []) do
    fn _request -> {:ok, %Response{status: status, headers: headers, body: body}} end
  end

  describe "insert_request/5" do
    test "assembles the multipart/related body with constant framing" do
      metadata = %{name: "uploads/img.png", contentType: "image/png"}

      request =
        Client.insert_request("bucket", metadata, "BYTES", [predefinedAcl: "publicRead"],
          boundary: "BOUNDARY"
        )

      assert %Request{method: :post, url: url, query: query, headers: headers, body: body} =
               request

      assert url == "https://storage.googleapis.com/upload/storage/v1/b/bucket/o"
      assert query == [uploadType: "multipart", predefinedAcl: "publicRead"]
      assert headers == [{"content-type", "multipart/related; boundary=BOUNDARY"}]

      assert IO.iodata_to_binary(body) ==
               "--BOUNDARY\r\n" <>
                 "Content-Type: application/json; charset=UTF-8\r\n\r\n" <>
                 Jason.encode!(metadata) <>
                 "\r\n--BOUNDARY\r\n" <>
                 "Content-Type: image/png\r\n\r\n" <>
                 "BYTES" <>
                 "\r\n--BOUNDARY--\r\n"
    end

    test "media part content type defaults to application/octet-stream" do
      request = Client.insert_request("bucket", %{name: "x"}, "BYTES", [], boundary: "B")

      assert IO.iodata_to_binary(request.body) =~ "\r\nContent-Type: application/octet-stream\r\n"
    end

    test "generated boundaries are unique and header-safe" do
      %Request{headers: [{"content-type", ct1}]} =
        Client.insert_request("bucket", %{name: "x"}, "BYTES")

      %Request{headers: [{"content-type", ct2}]} =
        Client.insert_request("bucket", %{name: "x"}, "BYTES")

      assert ct1 != ct2
      assert ct1 =~ ~r/^multipart\/related; boundary=waffle_gcs_[0-9a-f]{32}$/
    end

    test "rejects a contentType that could break out of the part header" do
      for bad <- [
            "image/png\r\nX-Evil: 1",
            "image/png\nX-Evil: 1",
            "image/png\n",
            :png,
            "imagé/png"
          ] do
        assert_raise ArgumentError, fn ->
          Client.insert_request("bucket", %{name: "x", contentType: bad}, "BYTES")
        end
      end
    end
  end

  describe "get_request/3, delete_request/2, list_request/2" do
    test "percent-encode the full object name, including slashes and reserved characters" do
      name = "uploads/img #1+é.png"
      encoded = "uploads%2Fimg%20%231%2B%C3%A9.png"

      assert Client.get_request("bucket", name).url ==
               "https://storage.googleapis.com/storage/v1/b/bucket/o/" <> encoded

      assert Client.delete_request("bucket", name).url ==
               "https://storage.googleapis.com/storage/v1/b/bucket/o/" <> encoded
    end

    test "list_request carries the query through" do
      request = Client.list_request("bucket", prefix: "uploads/", pageToken: "tok")

      assert request.url == "https://storage.googleapis.com/storage/v1/b/bucket/o"
      assert request.query == [prefix: "uploads/", pageToken: "tok"]
    end
  end

  describe "insert/4" do
    @object_json ~s({"name": "uploads/img.png", "bucket": "bucket", "size": "5", ) <>
                   ~s("generation": "123", "contentType": "image/png"})

    test "returns {:ok, %Object{}} with raw response on 2xx" do
      assert {:ok, %Object{} = object} =
               Client.insert(
                 "bucket",
                 "uploads/img.png",
                 {:binary, "BYTES"},
                 @opts ++ [respond: respond(200, @object_json)]
               )

      assert object.name == "uploads/img.png"
      assert object.bucket == "bucket"
      assert object.size == 5
      assert object.generation == "123"
      assert object.content_type == "image/png"
      assert %Response{status: 200, body: @object_json} = object.raw
    end

    test "authorizes with the configured token fetcher" do
      {:ok, _} =
        Client.insert(
          "bucket",
          "x",
          {:binary, ""},
          @opts ++ [respond: respond(200, @object_json)]
        )

      assert_received {:request, %Request{headers: headers}}
      assert {"authorization", "Bearer stub-token"} in headers
    end

    test "uploads from a file on disk" do
      path = Path.join(System.tmp_dir!(), "waffle_gcs_client_test_#{System.unique_integer()}")
      File.write!(path, "FILE BYTES")
      on_exit(fn -> File.rm(path) end)

      {:ok, _} =
        Client.insert(
          "bucket",
          "x",
          {:file, path},
          @opts ++ [respond: respond(200, @object_json)]
        )

      assert_received {:request, %Request{body: body}}
      assert IO.iodata_to_binary(body) =~ "FILE BYTES"
    end

    test "returns {:error, %Error{}} with the GCS message on HTTP failure" do
      body = ~s({"error": {"code": 403, "message": "Forbidden"}})

      assert {:error, %Error{status: 403, reason: "Forbidden", raw: %Response{status: 403}}} =
               Client.insert("bucket", "x", {:binary, ""}, @opts ++ [respond: respond(403, body)])
    end

    test "wraps connection-level failures with a nil status and raw" do
      assert {:error, %Error{status: nil, reason: :timeout, raw: nil}} =
               Client.insert(
                 "bucket",
                 "x",
                 {:binary, ""},
                 @opts ++ [respond: fn _ -> {:error, :timeout} end]
               )
    end
  end

  describe "get/3" do
    test "returns the object with ACLs under projection full" do
      body = ~s({"name": "x", "acl": [{"entity": "allUsers", "role": "READER"}]})

      assert {:ok, %Object{acl: [%{"entity" => "allUsers", "role" => "READER"}]}} =
               Client.get("bucket", "x", @opts ++ [respond: respond(200, body)])

      assert_received {:request, %Request{method: :get}}
    end
  end

  describe "delete/3" do
    test "returns :ok on 204" do
      assert :ok = Client.delete("bucket", "x", @opts ++ [respond: respond(204, "")])
    end

    test "returns {:error, %Error{}} on 404, keeping the unparseable body as reason" do
      assert {:error, %Error{status: 404, reason: "not json"}} =
               Client.delete("bucket", "x", @opts ++ [respond: respond(404, "not json")])
    end
  end

  describe "list/2" do
    test "maps items and the next page token" do
      body =
        ~s({"items": [{"name": "a", "size": "1"}, {"name": "b"}], "nextPageToken": "tok"})

      assert {:ok,
              %{
                items: [%Object{name: "a", size: 1, raw: nil}, %Object{name: "b"}],
                next_page_token: "tok"
              }} =
               Client.list("bucket", @opts ++ [respond: respond(200, body)])
    end

    test "an empty bucket maps to no items and no token" do
      assert {:ok, %{items: [], next_page_token: nil}} =
               Client.list("bucket", @opts ++ [respond: respond(200, "{}")])
    end
  end

  describe "Error.message/1" do
    test "renders HTTP and connection failures" do
      assert Exception.message(%Error{status: 403, reason: "Forbidden"}) =~ "status 403"
      assert Exception.message(%Error{status: nil, reason: :timeout}) =~ ":timeout"
    end
  end
end
