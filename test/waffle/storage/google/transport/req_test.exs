defmodule Waffle.Storage.Google.Transport.ReqTest do
  use ExUnit.Case, async: false

  alias Waffle.Storage.Google.Client.{Request, Response}
  alias Waffle.Storage.Google.Transport

  setup do
    Application.put_env(:waffle_gcs, Transport.Req, req_options: [plug: {Req.Test, __MODULE__}])

    on_exit(fn -> Application.delete_env(:waffle_gcs, Transport.Req) end)
  end

  test "translates the request and normalizes the response" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/upload/storage/v1/b/bucket/o"
      assert conn.query_string == "uploadType=multipart"
      assert Plug.Conn.get_req_header(conn, "x-test") == ["1"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body == "BODY"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"name":"x"}))
    end)

    request = %Request{
      method: :post,
      url: "https://storage.googleapis.com/upload/storage/v1/b/bucket/o",
      query: [uploadType: "multipart"],
      headers: [{"x-test", "1"}],
      body: "BODY"
    }

    assert {:ok, %Response{status: 200, body: ~s({"name":"x"}), raw: %Req.Response{}} = response} =
             Transport.Req.execute(request, [])

    assert Enum.all?(response.headers, fn {name, value} ->
             is_binary(name) and is_binary(value)
           end)
  end

  test "the body is not auto-decoded" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"kept": "verbatim"}))
    end)

    request = %Request{method: :get, url: "https://storage.googleapis.com/storage/v1/b/b/o"}

    assert {:ok, %Response{body: ~s({"kept": "verbatim"})}} = Transport.Req.execute(request, [])
  end

  test "connection-level failures return the transport's exception" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    request = %Request{method: :get, url: "https://storage.googleapis.com/storage/v1/b/b/o"}

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             Transport.Req.execute(request, [])
  end
end
