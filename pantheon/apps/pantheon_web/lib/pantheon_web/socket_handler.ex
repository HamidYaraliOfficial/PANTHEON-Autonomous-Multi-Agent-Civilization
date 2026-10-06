defmodule PantheonWeb.SocketHandler do
  @moduledoc """
  Raw Cowboy WebSocket handler (not a Plug — Cowboy websockets are set up
  through the dispatch table, see `PantheonWeb.Application`) that
  streams the world live to the dashboard: every world tick and every
  event published on `:event_bus` is forwarded as a JSON text frame.

  Client -> server messages are minimal by design: `{"type":"subscribe","topics":["world_tick","trade"]}`
  lets a client narrow what it wants pushed to it (useful once a world
  has thousands of events per second).
  """
  @behaviour :cowboy_websocket

  @impl true
  def init(req, state) do
    {:cowboy_websocket, req, state, %{idle_timeout: 60_000}}
  end

  @impl true
  def websocket_init(state) do
    :event_bus.subscribe(:all)
    {[{:text, Jason.encode!(%{type: "hello", status: PantheonCore.World.status()})}], state}
  end

  @impl true
  def websocket_handle({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"type" => "subscribe", "topics" => topics}} ->
        Enum.each(topics, fn t ->
          :event_bus.subscribe(String.to_atom(t))
        end)

        {[], state}

      {:ok, %{"type" => "ping"}} ->
        {[{:text, Jason.encode!(%{type: "pong"})}], state}

      _ ->
        {[], state}
    end
  end

  def websocket_handle(_frame, state), do: {[], state}

  @impl true
  def websocket_info({:pantheon_event, topic, event_map}, state) do
    payload = %{type: "event", topic: topic, event: sanitize(event_map)}
    {[{:text, Jason.encode!(payload)}], state}
  end

  def websocket_info(_info, state), do: {[], state}

  defp sanitize(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_pid(v) or is_reference(v) or is_function(v) end)
    |> Map.new(fn {k, v} -> {to_string(k), sanitize(v)} end)
  end

  defp sanitize(list) when is_list(list), do: Enum.map(list, &sanitize/1)
  defp sanitize(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> sanitize()
  defp sanitize(other), do: other
end
