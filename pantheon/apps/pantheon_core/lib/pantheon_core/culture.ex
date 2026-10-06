defmodule PantheonCore.Culture do
  @moduledoc """
  Culture Engine.

  Culture is modelled as a growing, traceable collection of norms,
  rituals, symbols and stories rather than a fixed label. Every element
  carries its origin (which tick, which trigger produced it), so the
  Culture Explorer can show *why* a norm exists, not just that it does.
  `drift/2` lets new elements emerge spontaneously over time; `contact/3`
  lets two civilizations' cultures influence each other (mixing,
  borrowing, fragmentation).
  """
  use GenServer

  @seed_norms ["share food with kin", "greet elders first", "mark the harvest"]
  @seed_symbols ["sun-circle", "twin-rivers", "hearth-flame"]

  # ---------------------------------------------------------------- API --

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def seed_culture(civ_id, world_seed) do
    GenServer.call(__MODULE__, {:seed, civ_id, world_seed})
  end

  def add_element(civ_id, kind, content, tick, trigger \\ :organic)
      when kind in [:norm, :ritual, :symbol, :story] do
    GenServer.call(__MODULE__, {:add, civ_id, kind, content, tick, trigger})
  end

  @doc "Spontaneous cultural evolution: occasionally invent something new."
  def drift(civ_id, tick), do: GenServer.cast(__MODULE__, {:drift, civ_id, tick})

  @doc "Cultural contact: civ_b adopts (a possibly altered copy of) one of civ_a's elements."
  def contact(civ_a, civ_b, tick), do: GenServer.cast(__MODULE__, {:contact, civ_a, civ_b, tick})

  def get_culture(civ_id), do: GenServer.call(__MODULE__, {:get, civ_id})

  # ----------------------------------------------------------- callbacks --

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:seed, civ_id, world_seed}, _from, state) do
    rng = PantheonCore.RNG.new(world_seed, {:culture, civ_id})
    {norms, rng} = PantheonCore.RNG.shuffle(@seed_norms, rng)
    {symbols, _rng} = PantheonCore.RNG.shuffle(@seed_symbols, rng)

    culture = %{
      civ_id: civ_id,
      norms: tag_all(Enum.take(norms, 2), 0, :founding),
      rituals: [],
      symbols: tag_all(Enum.take(symbols, 1), 0, :founding),
      stories: [],
      log: []
    }

    {:reply, :ok, Map.put(state, civ_id, culture)}
  end

  def handle_call({:add, civ_id, kind, content, tick, trigger}, _from, state) do
    case do_add_element(state, civ_id, kind, content, tick, trigger) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      :error -> {:reply, {:error, :unknown_civilization}, state}
    end
  end

  def handle_call({:get, civ_id}, _from, state), do: {:reply, Map.fetch(state, civ_id), state}

  @impl true
  def handle_cast({:drift, civ_id, tick}, state) do
    if Map.has_key?(state, civ_id) do
      case PantheonCore.Language.generate_name("lang-#{civ_id}", :city) do
        {:ok, %{name: city_name}} ->
          content = "the tale of #{city_name}"

          case do_add_element(state, civ_id, :story, content, tick, :emergent) do
            {:ok, new_state} -> {:noreply, new_state}
            :error -> {:noreply, state}
          end

        _ ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_cast({:contact, civ_a, civ_b, tick}, state) do
    with culture_a when not is_nil(culture_a) <- Map.get(state, civ_a),
         true <- Map.has_key?(state, civ_b),
         pool when pool != [] <- culture_a.norms ++ culture_a.symbols do
      {borrowed, _rng} = PantheonCore.RNG.pick(pool, PantheonCore.RNG.new(tick, {civ_a, civ_b}))
      kind = if borrowed in culture_a.norms, do: :norm, else: :symbol
      content = "borrowed: " <> to_string(borrowed.content)

      case do_add_element(state, civ_b, kind, content, tick, {:contact, civ_a}) do
        {:ok, new_state} -> {:noreply, new_state}
        :error -> {:noreply, state}
      end
    else
      _ -> {:noreply, state}
    end
  end

  # ------------------------------------------------------------ internal --

  defp do_add_element(state, civ_id, kind, content, tick, trigger) do
    case Map.fetch(state, civ_id) do
      {:ok, culture} ->
        key = plural(kind)
        element = %{content: content, tick: tick, origin: trigger, id: make_id()}
        updated = Map.update!(culture, key, &[element | &1])
        log_entry = %{kind: kind, content: content, tick: tick, origin: trigger}
        logged = %{updated | log: [log_entry | updated.log]}
        {:ok, Map.put(state, civ_id, logged)}

      :error ->
        :error
    end
  end

  defp tag_all(items, tick, origin) do
    Enum.map(items, fn content -> %{content: content, tick: tick, origin: origin, id: make_id()} end)
  end

  defp plural(:norm), do: :norms
  defp plural(:ritual), do: :rituals
  defp plural(:symbol), do: :symbols
  defp plural(:story), do: :stories

  defp make_id, do: :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
end
