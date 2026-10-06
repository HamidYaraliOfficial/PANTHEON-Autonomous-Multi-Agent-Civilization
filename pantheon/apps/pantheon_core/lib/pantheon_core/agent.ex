defmodule PantheonCore.Agent do
  @moduledoc """
  Elixir-side façade over `agent_actor` (erlang_engine). Everything here
  is a thin, documented wrapper around message sends to the actual OTP
  process that owns the agent's state — this module holds no state of
  its own.
  """

  @doc "Spawn a new agent into `region_id`'s supervisor. `attrs` seeds its initial state."
  def spawn(region_id, attrs) do
    with {:ok, region_sup} <- :region_partition_sup.region_pid(region_id) do
      init_state =
        attrs
        |> Map.put_new(:region, region_id)
        |> Map.put_new(:policy, {PantheonCore.Agent.LuaPolicyBridge, :decide})

      :region_agent_sup.start_agent(region_sup, init_state)
    end
  end

  def tick(agent_id) do
    with {:ok, pid} <- :world_registry.whereis_id({:agent, agent_id}) do
      :agent_actor.tick(pid)
    end
  end

  def get_state(agent_id) do
    with {:ok, pid} <- :world_registry.whereis_id({:agent, agent_id}) do
      :agent_actor.get_state(pid)
    end
  end

  def apply_event(agent_id, event_map) do
    with {:ok, pid} <- :world_registry.whereis_id({:agent, agent_id}) do
      :agent_actor.apply_event(pid, event_map)
    end
  end

  def sleep(agent_id, reason \\ :low_priority) do
    with {:ok, pid} <- :world_registry.whereis_id({:agent, agent_id}) do
      :agent_actor.sleep(pid, reason)
    end
  end

  def wake(agent_id) do
    with {:ok, pid} <- :world_registry.whereis_id({:agent, agent_id}) do
      :agent_actor.wake(pid)
    end
  end

  @doc "All agent ids currently registered anywhere in the world."
  def all_ids do
    :world_registry.all_of_kind(:agent) |> Enum.map(fn {id, _pid} -> id end)
  end
end

defmodule PantheonCore.Agent.LuaPolicyBridge do
  @moduledoc """
  Bridges `agent_actor`'s `{Mod, Fun}` policy callback to a Lua archetype
  script loaded through `PantheonCore.LuaEngine`. Selected by the
  agent's own `archetype` field, so different agents in the same region
  can run entirely different behaviour scripts.
  """

  @doc "Called directly from the Erlang `agent_actor` process as `Mod:Fun(SanitizedState)`."
  def decide(agent_snapshot) do
    archetype = Map.get(agent_snapshot, :archetype, "generic") |> to_string()
    script_id = "archetypes/" <> archetype

    ensure_loaded(script_id)

    case PantheonCore.LuaEngine.run_decision(script_id, agent_snapshot) do
      {:ok, action} when is_map(action) -> action
      _ -> raise "lua policy #{script_id} did not return a valid action"
    end
  end

  defp ensure_loaded(script_id) do
    if script_id not in PantheonCore.LuaEngine.list_scripts() do
      PantheonCore.LuaEngine.load_script(script_id)
    end
  end
end
