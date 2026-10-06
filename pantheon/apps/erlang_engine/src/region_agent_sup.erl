%%%-------------------------------------------------------------------------
%%% @doc Supervises every `agent_actor` living in a single world region.
%%%
%%% A crash in one agent (a bad Lua policy, an unexpected state) restarts
%%% only that agent, with its last-known-good memory snapshot reloaded by
%%% `pantheon_core.Snapshot`. Neighbours never notice.
%%%-------------------------------------------------------------------------
-module(region_agent_sup).
-behaviour(supervisor).

-export([start_link/1]).
-export([start_agent/2, stop_agent/2, agent_pid/1]).
-export([init/1]).

start_link(RegionId) ->
    supervisor:start_link(?MODULE, [RegionId]).

-spec start_agent(pid(), map()) -> {ok, pid()} | {error, term()}.
start_agent(SupPid, AgentInitState = #{id := AgentId}) ->
    ChildSpec = #{
        id => {agent_actor, AgentId},
        start => {agent_actor, start_link, [AgentInitState]},
        restart => transient,
        shutdown => 2000,
        type => worker
    },
    case supervisor:start_child(SupPid, ChildSpec) of
        {ok, Pid} ->
            world_registry:register_id({agent, AgentId}, Pid),
            {ok, Pid};
        {error, {already_started, Pid}} ->
            {ok, Pid};
        Error ->
            Error
    end.

stop_agent(SupPid, AgentId) ->
    _ = supervisor:terminate_child(SupPid, {agent_actor, AgentId}),
    _ = supervisor:delete_child(SupPid, {agent_actor, AgentId}),
    world_registry:unregister_id({agent, AgentId}),
    ok.

agent_pid(AgentId) ->
    world_registry:whereis_id({agent, AgentId}).

init([RegionId]) ->
    SupFlags = #{strategy => one_for_one, intensity => 200, period => 10},
    _ = RegionId,
    {ok, {SupFlags, []}}.
