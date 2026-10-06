defmodule PantheonCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :pantheon_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {PantheonCore.Application, []}
    ]
  end

  defp deps do
    [
      # Pure-Erlang Lua 5.3 interpreter — no native code, so Lua behaviour
      # scripts run inside the same sandboxed, supervised BEAM VM as
      # everything else (no shelling out, no filesystem/network access
      # unless we explicitly expose it as a Lua-callable function).
      {:luerl, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:erlang_engine, in_umbrella: true}
    ]
  end
end
