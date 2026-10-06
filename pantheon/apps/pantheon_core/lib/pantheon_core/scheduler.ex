defmodule PantheonCore.Scheduler do
  @moduledoc """
  World Scheduler: drives the tick loop at a wall-clock cadence
  (`:tick_ms`, adjustable at runtime through `PantheonCore.World.set_speed/1`),
  independent of the web layer so headless / long-horizon runs need no UI
  attached at all.
  """
  use GenServer

  @impl true
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_) do
    schedule_next(base_interval())
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    PantheonCore.World.advance_tick()
    speed = Map.get(PantheonCore.World.status(), :speed, 1)
    schedule_next(round(base_interval() / max(speed, 1)))
    {:noreply, state}
  end

  defp schedule_next(interval_ms) do
    Process.send_after(self(), :tick, max(interval_ms, 1))
  end

  defp base_interval, do: Application.get_env(:pantheon_core, :tick_ms, 250)
end
