defmodule PantheonWeb.Application do
  @moduledoc """
  Boots the HTTP + WebSocket endpoint. A single Cowboy listener serves
  both: `/ws` is wired directly to the raw `PantheonWeb.SocketHandler`,
  everything else goes through `PantheonWeb.Router` (REST API + static
  dashboard files).
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:pantheon_web, :http_port, 4000)

    dispatch =
      :cowboy_router.compile([
        {:_,
         [
           {"/ws", PantheonWeb.SocketHandler, []},
           {:_, Plug.Cowboy.Handler, {PantheonWeb.Router, []}}
         ]}
      ])

    children = [
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: PantheonWeb.Router,
        options: [port: port, dispatch: dispatch]
      )
    ]

    Logger.info("PANTHEON dashboard + API listening on http://localhost:#{port}")

    opts = [strategy: :one_for_one, name: PantheonWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
