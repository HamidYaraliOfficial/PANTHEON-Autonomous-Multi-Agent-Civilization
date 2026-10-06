%%%-------------------------------------------------------------------------
%%% @doc Root supervisor of the PANTHEON simulation core.
%%%
%%% Tree shape:
%%%
%%%   erlang_engine_sup            (one_for_one)
%%%     |- world_registry          (gen_server, ETS-backed id -> pid map)
%%%     |- event_bus               (gen_server, topic pub/sub)
%%%     |- region_partition_sup    (supervisor, one child per world region)
%%%
%%% A crash in one agent never reaches this level: agent_actor crashes are
%%% isolated by region_partition_sup, and a whole region crashing does not
%%% take down the registry, the event bus, or any other region.
%%%-------------------------------------------------------------------------
-module(erlang_engine_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 20, period => 10},

    Children = [
        #{id => world_registry,
          start => {world_registry, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker},

        #{id => event_bus,
          start => {event_bus, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker},

        #{id => region_partition_sup,
          start => {region_partition_sup, start_link, []},
          restart => permanent,
          shutdown => infinity,
          type => supervisor}
    ],

    {ok, {SupFlags, Children}}.
