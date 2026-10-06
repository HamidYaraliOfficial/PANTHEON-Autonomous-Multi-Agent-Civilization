defmodule PantheonWeb.Router do
  @moduledoc """
  REST + static-file surface. Every simulation-affecting endpoint here is
  a thin wrapper around a PantheonCore call — no business logic lives in
  this module. `/api/*` returns JSON; everything else falls through to
  the static frontend (the dashboard SPA in `frontend/`).
  """
  use Plug.Router
  require Logger

  plug Plug.Logger, log: :debug
  plug :cors
  plug :match
  plug :fetch_query_params

  # `pass: ["*/*"]` matters here: plain GET requests (and our own CORS
  # OPTIONS preflight) arrive with no JSON body and often no content-type
  # at all — without a catch-all `pass`, Plug.Parsers would raise
  # UnsupportedMediaTypeError for every one of them instead of just
  # leaving body_params empty.
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Jason

  plug :dispatch

  # ------------------------------------------------------------- world --

  get "/api/status" do
    json(conn, 200, PantheonCore.World.status())
  end

  post "/api/world/bootstrap" do
    config = atomize(conn.body_params)

    case PantheonCore.World.bootstrap(config) do
      {:ok, summary} -> json(conn, 200, summary)
      {:error, reason} -> json(conn, 422, %{error: inspect(reason)})
    end
  end

  post "/api/world/start" do
    PantheonCore.World.start_clock()
    json(conn, 200, PantheonCore.World.status())
  end

  post "/api/world/pause" do
    PantheonCore.World.pause_clock()
    json(conn, 200, PantheonCore.World.status())
  end

  post "/api/world/speed" do
    multiplier = Map.get(conn.body_params, "multiplier", 1)
    PantheonCore.World.set_speed(multiplier)
    json(conn, 200, PantheonCore.World.status())
  end

  # ----------------------------------------------------------- regions --

  get "/api/regions" do
    json(conn, 200, PantheonCore.World.list_regions())
  end

  get "/api/regions/:id" do
    case PantheonCore.World.get_region(id) do
      nil -> json(conn, 404, %{error: "region not found"})
      region -> json(conn, 200, region)
    end
  end

  get "/api/regions/:id/market" do
    case PantheonCore.Economy.get_market(id) do
      {:ok, market} -> json(conn, 200, market)
      :error -> json(conn, 404, %{error: "market not found"})
    end
  end

  # ------------------------------------------------------ civilizations --

  get "/api/civilizations" do
    json(conn, 200, PantheonCore.World.list_civilizations())
  end

  get "/api/civilizations/:id" do
    case PantheonCore.World.get_civilization(id) do
      nil -> json(conn, 404, %{error: "civilization not found"})
      civ -> json(conn, 200, civ)
    end
  end

  get "/api/civilizations/:id/culture" do
    case PantheonCore.Culture.get_culture(id) do
      {:ok, culture} -> json(conn, 200, Map.delete(culture, :log) |> Map.put(:recent_log, Enum.take(culture.log, 50)))
      :error -> json(conn, 404, %{error: "no culture recorded"})
    end
  end

  get "/api/civilizations/:id/language" do
    case PantheonCore.Language.get_language("lang-#{id}") do
      {:ok, lang} -> json(conn, 200, Map.take(lang, [:id, :consonants, :vowels, :lexicon, :history]))
      :error -> json(conn, 404, %{error: "no language recorded"})
    end
  end

  # ---------------------------------------------------------------- agents --

  get "/api/agents/:id" do
    case PantheonCore.Agent.get_state(id) do
      {:ok, state} -> json(conn, 200, state)
      _ -> json(conn, 404, %{error: "agent not found or dormant"})
    end
  end

  get "/api/agents" do
    json(conn, 200, %{ids: PantheonCore.Agent.all_ids()})
  end

  # -------------------------------------------------------------- history --

  get "/api/history" do
    limit = conn.params |> Map.get("limit", "100") |> to_int(100)
    topic = conn.params |> Map.get("topic", "all") |> String.to_atom()
    json(conn, 200, PantheonCore.History.recent(limit, topic))
  end

  # --------------------------------------------------------- operating hours --

  get "/api/operating-hours" do
    json(conn, 200, PantheonCore.OperatingHours.get_schedule())
  end

  put "/api/operating-hours" do
    :ok = PantheonCore.OperatingHours.set_schedule(conn.body_params)
    json(conn, 200, PantheonCore.OperatingHours.get_schedule())
  end

  get "/api/operating-hours/status" do
    status = PantheonCore.OperatingHours.status()
    json(conn, 200, %{
      open: status.open,
      next_state: status.next_state,
      changes_at: status.changes_at && DateTime.to_iso8601(status.changes_at),
      seconds_until_change: status.seconds_until_change
    })
  end

  # ----------------------------------------------------------------- misc --

  get "/healthz" do
    send_resp(conn, 200, "ok")
  end

  # CORS preflight for the PUT/POST JSON calls the dashboard makes from
  # a different origin during local development.
  options _ do
    send_resp(conn, 204, "")
  end

  match _ do
    static_root = Application.get_env(:pantheon_web, :static_dir, "frontend")
    Plug.Static.call(conn, Plug.Static.init(at: "/", from: static_root, only: ~w(index.html css js locales assets)))
    |> maybe_index(static_root)
  end

  # ------------------------------------------------------------- helpers --

  defp maybe_index(%Plug.Conn{state: :unset} = conn, static_root) do
    index_path = Path.join(static_root, "index.html")

    if File.exists?(index_path) do
      send_file(conn, 200, index_path)
    else
      send_resp(conn, 404, "not found")
    end
  end

  defp maybe_index(conn, _static_root), do: conn

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp cors(conn, _opts) do
    origin = Application.get_env(:pantheon_web, :cors_origin, "*")

    conn
    |> put_resp_header("access-control-allow-origin", origin)
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type")
  end

  defp to_int(str, default) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp atomize(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {safe_atom(k), v} end)
  end

  defp safe_atom(k) when is_atom(k), do: k

  defp safe_atom(k) when is_binary(k) do
    String.to_existing_atom(k)
  rescue
    ArgumentError -> String.to_atom(k)
  end
end
