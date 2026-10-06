import Config

# ---------------------------------------------------------------------------
# PANTHEON — Autonomous Multi-Agent Civilization
# Global configuration shared by every app in the umbrella.
# ---------------------------------------------------------------------------

config :pantheon_core,
  # Deterministic master seed. Two runs started with the same seed and the
  # same world configuration will produce the same history.
  world_seed: 1_337_042,
  world_name: "Aion Prime",
  tick_ms: 250,
  ticks_per_sim_day: 4,
  days_per_sim_year: 360,
  default_regions: 6,
  agents_per_region: 40,
  snapshot_dir: Path.expand("../../data/snapshots", __DIR__),
  lua_scripts_dir: Path.expand("../apps/pantheon_core/priv/lua", __DIR__)

config :pantheon_web,
  http_port: 4000,
  static_dir: Path.expand("../../frontend", __DIR__),
  cors_origin: "*"

config :logger, :console,
  format: "$time [$level] $metadata$message\n",
  metadata: [:module]

import_config "#{config_env()}.exs"
