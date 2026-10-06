defmodule PantheonCore.WorldGenTest do
  use ExUnit.Case, async: true

  alias PantheonCore.WorldGen

  test "generating the same region twice with the same seed is deterministic" do
    region_a = WorldGen.generate_region(123, 0)
    region_b = WorldGen.generate_region(123, 0)

    assert region_a == region_b
  end

  test "different indices produce different regions" do
    region_a = WorldGen.generate_region(123, 0)
    region_b = WorldGen.generate_region(123, 1)

    refute region_a.id == region_b.id
  end

  test "generate_world/3 returns the requested number of regions" do
    regions = WorldGen.generate_world(999, 5)
    assert length(regions) == 5
    assert Enum.map(regions, & &1.index) == [0, 1, 2, 3, 4]
  end

  test "every resource amount is non-negative" do
    region = WorldGen.generate_region(5, 2)

    for {_resource, amount} <- region.resources do
      assert amount >= 0
    end
  end
end
