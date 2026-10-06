defmodule PantheonCore.History do
  @moduledoc """
  Narrative History Engine / World Chronicle backbone.

  Subscribes to every topic on the low-level `:event_bus` and keeps an
  ordered, queryable event log — the raw material the World Chronicle,
  Timeline Viewer and Historical Search Engine are built on. Recent
  events are kept in memory (for the live dashboard feed); everything is
  also handed to `PantheonCore.Snapshot` for durable, replayable storage.
  """
  use GenServer
  require Logger

  @max_in_memory 5_000

  # ---------------------------------------------------------------- API --

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Most recent `limit` events, newest first. Optionally filter by topic."
  def recent(limit \\ 100, topic \\ :all) do
    GenServer.call(__MODULE__, {:recent, limit, topic})
  end

  @doc "Events between two tick numbers (inclusive), for the timeline slider."
  def between(from_tick, to_tick) do
    GenServer.call(__MODULE__, {:between, from_tick, to_tick})
  end

  def count, do: GenServer.call(__MODULE__, :count)

  def record(topic, event_map) when is_atom(topic) and is_map(event_map) do
    :event_bus.publish(topic, event_map)
  end

  # ----------------------------------------------------------- callbacks --

  @impl true
  def init(_) do
    :event_bus.subscribe(:all)
    {:ok, %{events: [], count: 0}}
  end

  @impl true
  def handle_call({:recent, limit, :all}, _from, state) do
    {:reply, Enum.take(state.events, limit), state}
  end

  def handle_call({:recent, limit, topic}, _from, state) do
    filtered =
      state.events
      |> Enum.filter(&(&1.topic == topic))
      |> Enum.take(limit)

    {:reply, filtered, state}
  end

  def handle_call({:between, from_tick, to_tick}, _from, state) do
    filtered =
      Enum.filter(state.events, fn e ->
        t = Map.get(e, :tick, Map.get(e, :bus_time, 0))
        t >= from_tick and t <= to_tick
      end)

    {:reply, filtered, state}
  end

  def handle_call(:count, _from, state), do: {:reply, state.count, state}

  @impl true
  def handle_info({:pantheon_event, topic, event_map}, state) do
    entry = Map.put(event_map, :topic, topic)
    new_events = [entry | state.events] |> Enum.take(@max_in_memory)
    PantheonCore.Snapshot.append_event(entry)
    {:noreply, %{state | events: new_events, count: state.count + 1}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
