defmodule Pantheon.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  defp deps do
    []
  end

  defp releases do
    [
      pantheon: [
        applications: [
          erlang_engine: :permanent,
          pantheon_core: :permanent,
          pantheon_web: :permanent
        ]
      ]
    ]
  end
end
