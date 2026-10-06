defmodule PantheonCore.World do
  @moduledoc """
  World orchestrator: owns the canonical calendar, region list and
  civilization roster, and is the entry point for the World Builder
  Wizard (`bootstrap/1`). Actual per-agent state lives in `agent_actor`
  processes (erlang_engine); this module tracks *which* ids exist and
  drives the tick loop that `PantheonCore.Scheduler` calls into.
  """
  use GenServer
  require Logger

  @archetypes ["farmer", "trader", "artisan"]

  defstruct seed: 0,
            name: "Unnamed World",
            tick: 0,
            day: 0,
            year: 0,
            running: false,
            speed: 1,
            regions: [],
            civilizations: [],
            config: %{}

  # ---------------------------------------------------------------- API --

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  World Builder Wizard entry point. `config` (all fields optional, with
  sane defaults) may include:

      %{seed: 42, name: "Aion Prime", num_regions: 6, num_civilizations: 2,
        agents_per_region: 40, resource_abundance: 1.0, biomes: [...]}
  """
  def bootstrap(config \\ %{}) do
    GenServer.call(__MODULE__, {:bootstrap, config}, 60_000)
  end

  def status, do: GenServer.call(__MODULE__, :status)

  def list_regions, do: GenServer.call(__MODULE__, :list_regions)

  def get_region(region_id), do: GenServer.call(__MODULE__, {:get_region, region_id})

  def list_civilizations, do: GenServer.call(__MODULE__, :list_civilizations)

  def get_civilization(civ_id), do: GenServer.call(__MODULE__, {:get_civilization, civ_id})

  def start_clock, do: GenServer.cast(__MODULE__, :start_clock)
  def pause_clock, do: GenServer.cast(__MODULE__, :pause_clock)
  def set_speed(multiplier) when multiplier > 0, do: GenServer.cast(__MODULE__, {:set_speed, multiplier})

  @doc "Advance the world by exactly one tick. Called by PantheonCore.Scheduler."
  def advance_tick, do: GenServer.cast(__MODULE__, :advance_tick)

  # ----------------------------------------------------------- callbacks --

  @impl true
  def init(_), do: {:ok, %__MODULE__{}}

  @impl true
  def handle_call({:bootstrap, config}, _from, _state) do
    world = do_bootstrap(config)
    {:reply, {:ok, summarize(world)}, world}
  end

  def handle_call(:status, _from, world), do: {:reply, summarize(world), world}

  def handle_call(:list_regions, _from, world), do: {:reply, world.regions, world}

  def handle_call({:get_region, region_id}, _from, world) do
    {:reply, Enum.find(world.regions, &(&1.id == region_id)), world}
  end

  def handle_call(:list_civilizations, _from, world), do: {:reply, world.civilizations, world}

  def handle_call({:get_civilization, civ_id}, _from, world) do
    {:reply, Enum.find(world.civilizations, &(&1.id == civ_id)), world}
  end

  @impl true
  def handle_cast(:start_clock, world), do: {:noreply, %{world | running: true}}
  def handle_cast(:pause_clock, world), do: {:noreply, %{world | running: false}}
  def handle_cast({:set_speed, mult}, world), do: {:noreply, %{world | speed: mult}}

  def handle_cast(:advance_tick, %{running: false} = world), do: {:noreply, world}

  def handle_cast(:advance_tick, world) do
    ticks_per_day = Application.get_env(:pantheon_core, :ticks_per_sim_day, 4)
    days_per_year = Application.get_env(:pantheon_core, :days_per_sim_year, 360)

    new_tick = world.tick + 1
    new_day = div(new_tick, ticks_per_day) + world.day
    day_rolled = rem(new_tick, ticks_per_day) == 0

    world =
      if day_rolled do
        tick_all_agents(world)
        PantheonCore.Economy.tick_all()
        maybe_drift_culture_and_language(world, new_day)
        %{world | day: new_day, year: div(new_day, days_per_year)}
      else
        world
      end
      |> Map.put(:tick, new_tick)

    :event_bus.publish(:world_tick, %{tick: new_tick, day: world.day, year: world.year})
    {:noreply, world}
  end

  # ------------------------------------------------------------ internal --

  defp do_bootstrap(config) do
    seed = Map.get(config, :seed, Application.get_env(:pantheon_core, :world_seed))
    name = Map.get(config, :name, Application.get_env(:pantheon_core, :world_name))
    num_regions = clamp(Map.get(config, :num_regions, 6), 1, 64)
    num_civs = clamp(Map.get(config, :num_civilizations, 2), 1, num_regions)
    agents_per_region = clamp(Map.get(config, :agents_per_region, 40), 1, 2_000)
    abundance = Map.get(config, :resource_abundance, 1.0)

    regions = PantheonCore.WorldGen.generate_world(seed, num_regions, abundance: abundance)

    Enum.each(regions, fn region ->
      {:ok, _pid} = :region_partition_sup.start_region(region.id)
      PantheonCore.Economy.init_market(region.id, %{})
    end)

    region_groups = Enum.chunk_every(regions, ceil(num_regions / num_civs))

    civilizations =
      region_groups
      |> Enum.with_index()
      |> Enum.map(fn {home_regions, idx} ->
        build_civilization(seed, idx, home_regions, agents_per_region)
      end)

    %__MODULE__{
      seed: seed,
      name: name,
      tick: 0,
      day: 0,
      year: 0,
      running: false,
      speed: 1,
      regions: regions,
      civilizations: civilizations,
      config: config
    }
  end

  defp build_civilization(seed, idx, home_regions, agents_per_region) do
    civ_id = "civ-#{idx}"
    {:ok, _lang_id} = PantheonCore.Language.create_language(civ_id, seed)
    :ok = PantheonCore.Culture.seed_culture(civ_id, seed)
    {:ok, %{name: civ_name}} = PantheonCore.Language.generate_name("lang-#{civ_id}", :civilization)

    Enum.each(home_regions, fn region ->
      spawn_population(seed, civ_id, region.id, agents_per_region)
    end)

    %{
      id: civ_id,
      name: civ_name,
      home_regions: Enum.map(home_regions, & &1.id),
      founded_tick: 0
    }
  end

  defp spawn_population(seed, civ_id, region_id, count) do
    rng = PantheonCore.RNG.new(seed, {:population, region_id})

    Enum.reduce(1..count, rng, fn i, r ->
      {archetype, r2} = PantheonCore.RNG.pick(@archetypes, r)
      agent_id = "#{region_id}-agent-#{i}"
      {:ok, %{name: given_name}} = PantheonCore.Language.generate_name("lang-#{civ_id}", :person)

      {:ok, _pid} =
        PantheonCore.Agent.spawn(region_id, %{
          id: agent_id,
          civ_id: civ_id,
          archetype: archetype,
          name: given_name,
          world_seed: seed
        })

      r2
    end)

    :ok
  end

  defp tick_all_agents(_world) do
    PantheonCore.Agent.all_ids()
    |> Enum.each(fn id ->
      case :world_registry.whereis_id({:agent, id}) do
        {:ok, pid} -> :agent_actor.tick(pid)
        :error -> :ok
      end
    end)
  end

  defp maybe_drift_culture_and_language(world, day) do
    if rem(day, 7) == 0 do
      Enum.each(world.civilizations, fn civ ->
        PantheonCore.Culture.drift(civ.id, day)
        PantheonCore.Language.drift("lang-#{civ.id}", day)
      end)
    end
  end

  defp clamp(val, min, _max) when val < min, do: min
  defp clamp(val, _min, max) when val > max, do: max
  defp clamp(val, _min, _max), do: val

  defp summarize(world) do
    %{
      name: world.name,
      seed: world.seed,
      tick: world.tick,
      day: world.day,
      year: world.year,
      running: world.running,
      speed: world.speed,
      region_count: length(world.regions),
      civilization_count: length(world.civilizations),
      population: length(PantheonCore.Agent.all_ids())
    }
  end
end
