defmodule PantheonWeb.RouterTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  @opts PantheonWeb.Router.init([])

  test "GET /healthz returns 200 ok" do
    conn = conn(:get, "/healthz") |> PantheonWeb.Router.call(@opts)
    assert conn.status == 200
    assert conn.resp_body == "ok"
  end

  test "GET /api/status returns JSON" do
    conn = conn(:get, "/api/status") |> PantheonWeb.Router.call(@opts)
    assert conn.status == 200
    assert {"content-type", "application/json"} in conn.resp_headers
    assert {:ok, _decoded} = Jason.decode(conn.resp_body)
  end

  test "GET /api/operating-hours returns the configured schedule" do
    conn = conn(:get, "/api/operating-hours") |> PantheonWeb.Router.call(@opts)
    assert conn.status == 200
    {:ok, decoded} = Jason.decode(conn.resp_body)
    assert Map.has_key?(decoded, "monday")
  end
end
