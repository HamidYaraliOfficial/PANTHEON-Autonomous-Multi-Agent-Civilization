defmodule PantheonCore.Economy do
  @moduledoc """
  Economic Engine (Multi-Market Economy).

  Every region owns its own local market. Prices are *not* looked up from
  a fixed table: each trade nudges the region's stock of a resource, and
  price is recomputed from the ratio between current stock and a
  slow-moving "expected" stock level — the same feedback loop that makes
  real local markets diverge from each other until trade routes arbitrage
  them back together (see `transfer/4`, used by trade-route logic).
  """
  use GenServer

  @base_prices %{
    food: 1.0, water: 0.5, wood: 1.2, stone: 1.5, metal: 4.0,
    fiber: 1.0, clay: 0.8, fish: 1.3
  }
  @elasticity 0.6

  # ---------------------------------------------------------------- API --

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init_market(region_id, initial_stock) do
    GenServer.call(__MODULE__, {:init_market, region_id, initial_stock})
  end

  @doc "Buy/sell `qty` of `resource` in `region_id`'s market. Returns {:ok, unit_price}."
  def trade(region_id, resource, qty, direction) when direction in [:buy, :sell] do
    GenServer.call(__MODULE__, {:trade, region_id, resource, qty, direction})
  end

  @doc "Move goods between two regions' markets (the basis of trade routes)."
  def transfer(from_region, to_region, resource, qty) do
    GenServer.call(__MODULE__, {:transfer, from_region, to_region, resource, qty})
  end

  def get_market(region_id), do: GenServer.call(__MODULE__, {:get, region_id})

  def all_markets, do: GenServer.call(__MODULE__, :all)

  @doc "Natural regeneration / demand drift, called once per sim day."
  def tick_all, do: GenServer.cast(__MODULE__, :tick_all)

  # ----------------------------------------------------------- callbacks --

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:init_market, region_id, initial_stock}, _from, state) do
    market = %{
      stock: Map.merge(%{food: 500.0, water: 500.0, wood: 200.0, stone: 100.0,
                          metal: 30.0, fiber: 150.0, clay: 100.0, fish: 100.0}, initial_stock),
      expected: %{},
      prices: @base_prices,
      volume_history: []
    }

    {:reply, :ok, Map.put(state, region_id, market)}
  end

  def handle_call({:trade, region_id, resource, qty, direction}, _from, state) do
    with {:ok, market} <- Map.fetch(state, region_id) do
      current = Map.get(market.stock, resource, 0.0)

      case direction do
        :sell when current < qty ->
          {:reply, {:error, :insufficient_stock}, state}

        _ ->
          delta = if direction == :buy, do: qty, else: -qty
          new_stock = max(current + delta, 0.01)
          expected = Map.get(market.expected, resource, current)
          price = repriced(Map.get(@base_prices, resource, 1.0), expected, new_stock)

          new_market = %{
            market
            | stock: Map.put(market.stock, resource, new_stock),
              prices: Map.put(market.prices, resource, price),
              volume_history: trim([%{resource: resource, qty: qty, direction: direction, price: price} | market.volume_history])
          }

          publish_event(:trade, %{region: region_id, resource: resource, qty: qty, direction: direction, price: price})
          {:reply, {:ok, price}, Map.put(state, region_id, new_market)}
      end
    else
      :error -> {:reply, {:error, :unknown_market}, state}
    end
  end

  def handle_call({:transfer, from_id, to_id, resource, qty}, _from, state) do
    with {:ok, from_m} <- Map.fetch(state, from_id),
         {:ok, to_m} <- Map.fetch(state, to_id),
         true <- Map.get(from_m.stock, resource, 0.0) >= qty do
      new_from = update_in(from_m.stock[resource], &(&1 - qty))
      new_to = update_in(to_m.stock[resource], fn v -> (v || 0.0) + qty end)
      publish_event(:trade_route, %{from: from_id, to: to_id, resource: resource, qty: qty})
      {:reply, :ok, state |> Map.put(from_id, new_from) |> Map.put(to_id, new_to)}
    else
      _ -> {:reply, {:error, :transfer_failed}, state}
    end
  end

  def handle_call({:get, region_id}, _from, state), do: {:reply, Map.fetch(state, region_id), state}
  def handle_call(:all, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:tick_all, state) do
    new_state =
      Map.new(state, fn {region_id, market} ->
        new_stock =
          Map.new(market.stock, fn {resource, qty} ->
            # Slow natural regeneration toward a comfortable buffer.
            regen = if qty < 1000, do: qty * 0.01, else: 0.0
            {resource, qty + regen}
          end)

        {region_id, %{market | stock: new_stock}}
      end)

    {:noreply, new_state}
  end

  # ------------------------------------------------------------ internal --

  defp repriced(base, expected, stock) when expected > 0 do
    ratio = expected / stock
    Float.round(base * :math.pow(ratio, @elasticity), 3)
  end

  defp repriced(base, _expected, _stock), do: base

  defp trim(list), do: Enum.take(list, 200)

  defp publish_event(topic, map) do
    :event_bus.publish(topic, map)
  end
end
