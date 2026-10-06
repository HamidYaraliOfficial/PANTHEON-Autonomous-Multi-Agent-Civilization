%%%-------------------------------------------------------------------------
%%% @doc Owns exactly one `region_agent_sup` child per active world region.
%%%
%%% This is the "spatial partitioning" layer described in the PANTHEON
%%% design: agents that are geographically close are supervised together,
%%% so a regional catastrophe (mass crash, region migration storm) is
%%% isolated from every other region, and cross-region agent messaging is
%%% the only place that pays "distributed" overhead.
%%%-------------------------------------------------------------------------
-module(region_partition_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([start_region/1, stop_region/1, region_pid/1]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec start_region(term()) -> {ok, pid()} | {error, term()}.
start_region(RegionId) ->
    ChildSpec = #{
        id => {region_agent_sup, RegionId},
        start => {region_agent_sup, start_link, [RegionId]},
        restart => permanent,
        shutdown => 5000,
        type => supervisor
    },
    case supervisor:start_child(?MODULE, ChildSpec) of
        {ok, Pid} ->
            world_registry:register_id({region, RegionId}, Pid),
            {ok, Pid};
        {error, {already_started, Pid}} ->
            {ok, Pid};
        Error ->
            Error
    end.

stop_region(RegionId) ->
    _ = supervisor:terminate_child(?MODULE, {region_agent_sup, RegionId}),
    _ = supervisor:delete_child(?MODULE, {region_agent_sup, RegionId}),
    world_registry:unregister_id({region, RegionId}),
    ok.

region_pid(RegionId) ->
    world_registry:whereis_id({region, RegionId}).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 50, period => 10},
    {ok, {SupFlags, []}}.
