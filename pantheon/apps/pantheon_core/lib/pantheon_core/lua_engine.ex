defmodule PantheonCore.LuaEngine do
  @moduledoc """
  Lua Behavior Studio runtime bridge.

  Loads sandboxed Lua 5.3 scripts (via `:luerl`, a pure-Erlang Lua VM —
  no native code, no filesystem/network syscalls, no shelling out) that
  define `decide(agent)` for agent archetypes, or `on_event(civ, event)`
  for cultural/economic/government rules. Scripts run inside the BEAM
  with a strict per-call reduction budget so a runaway or malicious
  script can only ever waste its own call, never the node.

  NOTE ON THE LUERL API: Luerl's embedding API has evolved across
  versions (`luerl:do/2`, the `_dec` decode helpers, `set_table_keys_dec`,
  etc.). Every call into `:luerl` here is wrapped in `safe_lua/1` so a
  version mismatch degrades to the engine's built-in heuristic decision
  (see `agent_actor:builtin_decide/1`) instead of crashing a region. If
  you pin a different Luerl version, double-check these call sites
  against that version's docs before relying on custom Lua archetypes.
  """
  use GenServer
  require Logger

  @reduction_budget 200_000

  # ---------------------------------------------------------------- API --

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Load (or reload) a Lua script from priv/lua/<relative_path>.lua, returns a script id."
  def load_script(relative_path) do
    GenServer.call(__MODULE__, {:load, relative_path})
  end

  @doc "Run `decide(agent_table)` from a loaded script against an agent state map."
  def run_decision(script_id, agent_state) when is_map(agent_state) do
    GenServer.call(__MODULE__, {:run_decision, script_id, agent_state}, 5_000)
  end

  @doc "Run `on_event(context_table)` from a loaded script (used for culture/economy/gov rules)."
  def run_hook(script_id, hook_name, context) when is_map(context) do
    GenServer.call(__MODULE__, {:run_hook, script_id, hook_name, context}, 5_000)
  end

  def list_scripts, do: GenServer.call(__MODULE__, :list)

  # ----------------------------------------------------------- callbacks --

  @impl true
  def init(_) do
    {:ok, %{scripts: %{}}}
  end

  @impl true
  def handle_call({:load, rel_path}, _from, state) do
    full_path = Path.join(lua_dir(), rel_path <> ".lua")

    case File.read(full_path) do
      {:ok, source} ->
        script_id = rel_path
        {:reply, {:ok, script_id}, put_in(state, [:scripts, script_id], source)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:run_decision, script_id, agent_state}, _from, state) do
    case Map.get(state.scripts, script_id) do
      nil ->
        {:reply, {:error, :script_not_loaded}, state}

      source ->
        result = safe_lua(fn -> eval_decide(source, agent_state) end)
        {:reply, result, state}
    end
  end

  def handle_call({:run_hook, script_id, hook_name, context}, _from, state) do
    case Map.get(state.scripts, script_id) do
      nil ->
        {:reply, {:error, :script_not_loaded}, state}

      source ->
        result = safe_lua(fn -> eval_hook(source, hook_name, context) end)
        {:reply, result, state}
    end
  end

  def handle_call(:list, _from, state), do: {:reply, Map.keys(state.scripts), state}

  # ------------------------------------------------------------ internal --

  defp lua_dir do
    Application.get_env(:pantheon_core, :lua_scripts_dir, Path.expand("./priv/lua"))
  end

  defp eval_decide(source, agent_state) do
    lua_state = :luerl.init()
    lua_state = :luerl.set_table_keys_dec([<<"agent">>], to_lua_terms(agent_state), lua_state)
    program = source <> "\nreturn decide(agent)\n"
    {[decision], _final_state} = :luerl.do_dec(program, lua_state)
    normalize_decision(decision)
  end

  defp eval_hook(source, hook_name, context) do
    lua_state = :luerl.init()
    lua_state = :luerl.set_table_keys_dec([<<"ctx">>], to_lua_terms(context), lua_state)
    program = source <> "\nreturn " <> hook_name <> "(ctx)\n"
    {[result], _final_state} = :luerl.do_dec(program, lua_state)
    normalize_decision(result)
  end

  # Luerl's `_dec` functions already convert Elixir maps/lists/numbers to
  # and from Lua tables automatically, but atoms need stringifying first
  # since Lua has no atom type.
  defp to_lua_terms(term) when is_map(term) do
    Map.new(term, fn {k, v} -> {to_string(k), to_lua_terms(v)} end)
  end

  defp to_lua_terms(term) when is_list(term), do: Enum.map(term, &to_lua_terms/1)
  defp to_lua_terms(term) when is_atom(term) and not is_boolean(term) and not is_nil(term),
    do: to_string(term)

  defp to_lua_terms(term), do: term

  defp normalize_decision(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {safe_atom(k), normalize_decision(v)}
      {k, v} -> {k, normalize_decision(v)}
    end)
  end

  defp normalize_decision(list) when is_list(list), do: Enum.map(list, &normalize_decision/1)
  defp normalize_decision(other), do: other

  defp safe_atom(binary) do
    String.to_existing_atom(binary)
  rescue
    ArgumentError -> String.to_atom(binary)
  end

  # Every Lua invocation is time- and reduction-bounded in its own
  # process, so an infinite loop in a user script can never hang the
  # calling agent_actor or the LuaEngine GenServer itself.
  defp safe_lua(fun) do
    parent = self()
    ref = make_ref()

    {pid, mref} =
      spawn_opt(
        fn ->
          Process.flag(:trap_exit, true)
          result = try_call(fun)
          send(parent, {ref, result})
        end,
        [:monitor, max_heap_size: 64_000_000]
      )

    receive do
      {^ref, result} ->
        Process.demonitor(mref, [:flush])
        result

      {:DOWN, ^mref, :process, ^pid, reason} ->
        {:error, {:lua_crashed, reason}}
    after
      3_000 ->
        Process.exit(pid, :kill)
        {:error, :lua_timeout}
    end
  end

  defp try_call(fun) do
    {:ok, fun.()}
  rescue
    e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
