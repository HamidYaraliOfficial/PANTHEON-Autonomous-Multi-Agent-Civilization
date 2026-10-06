defmodule PantheonCore.WorldGen do
  @moduledoc """
  Procedural World Generation Engine.

  Produces the geography, climate and starting resource distribution for
  every region of a freshly bootstrapped world, entirely as a pure
  function of `{world_seed, region_index}` — the same seed always
  produces the same planet, which is what makes deterministic replay and
  the Counterfactual Lab possible.
  """

  @biomes [:temperate_plains, :savanna, :taiga, :desert, :wetland, :highland, :coastal, :tundra]
  @resources [:food, :water, :wood, :stone, :metal, :fiber, :clay, :fish]
  @hazards [:drought, :flood, :storm, :earthquake, :none, :none, :none]

  @type region :: %{
          id: String.t(),
          index: non_neg_integer(),
          biome: atom(),
          climate: map(),
          resources: map(),
          fertility: float(),
          water_access: float(),
          hazard_profile: atom(),
          coordinates: {float(), float()}
        }

  @spec generate_region(integer(), non_neg_integer(), keyword()) :: region()
  def generate_region(world_seed, index, opts \\ []) do
    rng = PantheonCore.RNG.new(world_seed, {:region_gen, index})
    {biome, rng} = PantheonCore.RNG.pick(Keyword.get(opts, :biomes, @biomes), rng)
    {fertility, rng} = PantheonCore.RNG.uniform(rng)
    {water_access, rng} = PantheonCore.RNG.uniform(rng)
    {hazard, rng} = PantheonCore.RNG.pick(@hazards, rng)
    {temp_c, rng} = PantheonCore.RNG.range(-10, 38, rng)
    {rainfall_mm, rng} = PantheonCore.RNG.range(50, 3000, rng)
    {lat, rng} = PantheonCore.RNG.range(-90, 90, rng)
    {lon, _rng} = PantheonCore.RNG.range(-180, 180, rng)

    %{
      id: "region-#{index}",
      index: index,
      biome: biome,
      climate: %{avg_temp_c: temp_c, annual_rainfall_mm: rainfall_mm, hazard: hazard},
      resources: generate_resources(world_seed, index, biome, Keyword.get(opts, :abundance, 1.0)),
      fertility: Float.round(fertility, 3),
      water_access: Float.round(water_access, 3),
      hazard_profile: hazard,
      coordinates: {lat * 1.0, lon * 1.0}
    }
  end

  @spec generate_world(integer(), non_neg_integer(), keyword()) :: [region()]
  def generate_world(world_seed, num_regions, opts \\ []) do
    for i <- 0..(num_regions - 1), do: generate_region(world_seed, i, opts)
  end

  defp generate_resources(world_seed, index, biome, abundance) do
    rng = PantheonCore.RNG.new(world_seed, {:resources, index})
    base = biome_resource_bias(biome)

    Enum.reduce(@resources, {%{}, rng}, fn resource, {acc, r} ->
      {roll, r2} = PantheonCore.RNG.uniform(r)
      bias = Map.get(base, resource, 0.3)
      amount = Float.round(roll * bias * abundance * 1000, 1)
      {Map.put(acc, resource, amount), r2}
    end)
    |> elem(0)
  end

  defp biome_resource_bias(:temperate_plains), do: %{food: 0.9, water: 0.7, wood: 0.4}
  defp biome_resource_bias(:savanna), do: %{food: 0.6, water: 0.3, fiber: 0.5}
  defp biome_resource_bias(:taiga), do: %{wood: 0.9, food: 0.3, fish: 0.4}
  defp biome_resource_bias(:desert), do: %{stone: 0.6, metal: 0.5, water: 0.1}
  defp biome_resource_bias(:wetland), do: %{fish: 0.9, food: 0.6, clay: 0.5}
  defp biome_resource_bias(:highland), do: %{stone: 0.9, metal: 0.8, wood: 0.3}
  defp biome_resource_bias(:coastal), do: %{fish: 0.8, water: 0.9, food: 0.5}
  defp biome_resource_bias(:tundra), do: %{water: 0.4, fish: 0.3, wood: 0.1}
  defp biome_resource_bias(_), do: %{}
end
