defmodule ErlangEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :erlang_engine,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      erlc_options: [:debug_info, :warnings_as_errors],
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {:erlang_engine_app, []}
    ]
  end
end
