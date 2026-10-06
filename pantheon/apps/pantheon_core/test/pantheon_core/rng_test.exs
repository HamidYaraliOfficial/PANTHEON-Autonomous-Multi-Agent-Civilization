defmodule PantheonCore.RNGTest do
  use ExUnit.Case, async: true

  alias PantheonCore.RNG

  test "the same seed and stream id always produce the same sequence" do
    stream_a = RNG.new(42, :test_stream)
    stream_b = RNG.new(42, :test_stream)

    {values_a, _} = RNG.draw_many(stream_a, 20, &RNG.uniform/1)
    {values_b, _} = RNG.draw_many(stream_b, 20, &RNG.uniform/1)

    assert values_a == values_b
  end

  test "different stream ids diverge even with the same world seed" do
    {values_a, _} = RNG.draw_many(RNG.new(42, :a), 20, &RNG.uniform/1)
    {values_b, _} = RNG.draw_many(RNG.new(42, :b), 20, &RNG.uniform/1)

    refute values_a == values_b
  end

  test "range/3 always stays within [low, high]" do
    stream = RNG.new(7, :range_test)

    {values, _} =
      RNG.draw_many(stream, 200, fn s -> RNG.range(3, 9, s) end)

    assert Enum.all?(values, &(&1 >= 3 and &1 <= 9))
  end

  test "shuffle/2 is a permutation of the input" do
    {shuffled, _} = RNG.shuffle([1, 2, 3, 4, 5], RNG.new(1, :shuffle_test))
    assert Enum.sort(shuffled) == [1, 2, 3, 4, 5]
  end
end
