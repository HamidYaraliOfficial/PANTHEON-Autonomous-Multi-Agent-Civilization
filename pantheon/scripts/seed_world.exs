# PANTHEON — headless world bootstrap
#
# Usage (from the repository root, after `mix deps.get`):
#
#   mix run scripts/seed_world.exs
#
# Generates a world from the umbrella's default configuration
# (config/config.exs) and immediately starts its clock — useful for
# "Headless Mode" long-horizon runs with no dashboard attached, or as a
# quick smoke test that the whole umbrella boots and simulates correctly.

{:ok, summary} = PantheonCore.World.bootstrap(%{})
IO.puts("World bootstrapped: #{inspect(summary)}")

PantheonCore.World.start_clock()
IO.puts("Clock started. Press Ctrl+C twice to stop.")

Process.sleep(:infinity)
