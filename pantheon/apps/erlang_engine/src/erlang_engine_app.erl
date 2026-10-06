%%%-------------------------------------------------------------------------
%%% @doc PANTHEON :: erlang_engine
%%%
%%% Application entry point for the low-level, language-agnostic
%%% simulation core. This layer owns nothing but raw actor processes,
%%% supervision, deterministic randomness and message passing. It knows
%%% nothing about HTTP, JSON, Lua or the web dashboard — those concerns
%%% live one layer up, in `pantheon_core` / `pantheon_web` (Elixir).
%%%-------------------------------------------------------------------------
-module(erlang_engine_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    erlang_engine_sup:start_link().

stop(_State) ->
    ok.
