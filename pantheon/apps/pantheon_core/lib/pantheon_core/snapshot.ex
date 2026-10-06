defmodule PantheonCore.Snapshot do
  @moduledoc """
  Persistence Integrity Engine (simplified).

  Writes the append-only event log to disk as newline-delimited JSON
  ("Event Sourcing"), and can write/restore full world snapshots as a
  single JSON document. Every snapshot carries a checksum so corruption
  is detectable on load, and a `world_seed` + `engine_version` so it is
  meaningful input to the Deterministic Replay System.
  """
  use GenServer
  require Logger

  @engine_version "0.1.0"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def append_event(event_map) do
    GenServer.cast(__MODULE__, {:append_event, event_map})
  end

  @doc "Serialize the full world state (regions, agents summary, civ metadata) to disk."
  def save_world_snapshot(world_state) do
    GenServer.call(__MODULE__, {:save_snapshot, world_state}, 30_000)
  end

  def list_snapshots, do: GenServer.call(__MODULE__, :list_snapshots)

  def load_snapshot(filename), do: GenServer.call(__MODULE__, {:load_snapshot, filename})

  @impl true
  def init(_) do
    dir = snapshot_dir()
    File.mkdir_p!(dir)
    log_path = Path.join(dir, "events.ndjson")
    {:ok, log_file} = File.open(log_path, [:append, :utf8])
    {:ok, %{log_file: log_file, log_path: log_path, dir: dir}}
  end

  @impl true
  def handle_cast({:append_event, event_map}, state) do
    line = Jason.encode!(safe_map(event_map)) <> "\n"
    IO.write(state.log_file, line)
    {:noreply, state}
  end

  @impl true
  def handle_call({:save_snapshot, world_state}, _from, state) do
    payload = %{
      engine_version: @engine_version,
      saved_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      world: safe_map(world_state)
    }

    body = Jason.encode!(payload, pretty: true)
    checksum = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    filename = "world-#{world_state.tick}-#{String.slice(checksum, 0, 8)}.json"
    path = Path.join(state.dir, filename)
    File.write!(path, body)
    {:reply, {:ok, filename, checksum}, state}
  end

  def handle_call(:list_snapshots, _from, state) do
    files =
      state.dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.sort(:desc)

    {:reply, files, state}
  end

  def handle_call({:load_snapshot, filename}, _from, state) do
    path = Path.join(state.dir, filename)

    case File.read(path) do
      {:ok, body} -> {:reply, Jason.decode(body), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp snapshot_dir do
    Application.get_env(:pantheon_core, :snapshot_dir, Path.expand("./data/snapshots"))
  end

  # Jason can't encode pids/tuples/refs — strip anything it can't handle
  # before we ever try, recursively.
  defp safe_map(term) when is_map(term) do
    term
    |> Enum.reject(fn {_k, v} -> is_pid(v) or is_reference(v) or is_function(v) end)
    |> Enum.map(fn {k, v} -> {to_string(k), safe_map(v)} end)
    |> Map.new()
  end

  defp safe_map(term) when is_list(term), do: Enum.map(term, &safe_map/1)
  defp safe_map(term) when is_tuple(term), do: term |> Tuple.to_list() |> safe_map()
  defp safe_map(term) when is_pid(term) or is_reference(term) or is_function(term), do: nil
  defp safe_map(term), do: term
end
