defmodule PantheonCore.RNG do
  @moduledoc """
  Thin Elixir façade over `:det_rng` (erlang_engine). Every subsystem that
  needs randomness derives its own named stream from the world seed, so
  re-running the same seed reproduces the same world bit-for-bit,
  regardless of process scheduling order.
  """

  @type stream :: term()

  @spec new(integer(), term()) :: stream()
  def new(world_seed, stream_id), do: :det_rng.new(world_seed, stream_id)

  @spec uniform(stream()) :: {float(), stream()}
  def uniform(stream), do: :det_rng.uniform(stream)

  @spec range(integer(), integer(), stream()) :: {integer(), stream()}
  def range(low, high, stream), do: :det_rng.uniform_range(low, high, stream)

  @spec pick(list(any()), stream()) :: {any(), stream()}
  def pick(list, stream), do: :det_rng.pick(list, stream)

  @spec roll(float(), stream()) :: {boolean(), stream()}
  def roll(p, stream), do: :det_rng.roll(p, stream)

  @spec shuffle(list(any()), stream()) :: {list(any()), stream()}
  def shuffle(list, stream), do: :det_rng.shuffle(list, stream)

  @doc "Draw N values with `fun.(stream) -> {value, new_stream}` and return {values, stream}."
  def draw_many(stream, n, fun) do
    Enum.map_reduce(1..n, stream, fn _, s -> fun.(s) end)
  end
end
