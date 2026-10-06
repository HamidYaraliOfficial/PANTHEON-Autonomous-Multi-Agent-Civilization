defmodule PantheonCore.Application do
  @moduledoc """
  PANTHEON control plane supervisor.

  `erlang_engine` (the raw actor/supervision core) is started automatically
  as an umbrella application dependency before this tree boots. Everything
  below is Elixir: world orchestration, the Lua bridge, economy/culture/
  language subsystems, the historical event log, snapshotting and the
  configurable operating-hours schedule used by the dashboard.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: PantheonCore.Registry},
      PantheonCore.LuaEngine,
      PantheonCore.History,
      PantheonCore.Economy,
      PantheonCore.Culture,
      PantheonCore.Language,
      PantheonCore.OperatingHours,
      PantheonCore.Snapshot,
      PantheonCore.World,
      PantheonCore.Scheduler
    ]

    opts = [strategy: :rest_for_one, name: PantheonCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
