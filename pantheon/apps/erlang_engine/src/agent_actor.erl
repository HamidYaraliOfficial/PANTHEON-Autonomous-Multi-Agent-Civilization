%%%-------------------------------------------------------------------------
%%% @doc One `agent_actor` process = one living agent in the simulation.
%%%
%%% Holds the raw, language-agnostic state described in the PANTHEON
%%% design: identity, needs, goals, personality, a bounded memory, social
%%% relationships and an activity mode (`active | sleeping | dormant`).
%%%
%%% Decision-making itself is pluggable: `agent_actor` never hard-codes
%%% "what an agent should do". On every tick it delegates to a policy
%%% callback (`{Mod, Fun}`, injected by `pantheon_core`, normally backed by
%%% a Lua script executed through Luerl). If no policy is configured the
%%% engine falls back to a tiny built-in heuristic so this app is fully
%%% testable in isolation, with zero knowledge of Elixir or Lua.
%%%-------------------------------------------------------------------------
-module(agent_actor).
-behaviour(gen_server).

-export([start_link/1]).
-export([tick/1, wake/1, sleep/2, apply_event/2, get_state/1, set_policy/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(MAX_MEMORY, 64).
-define(MAX_RELATIONSHIPS, 256).

%% ------------------------------------------------------------------ API --

start_link(InitState) when is_map(InitState) ->
    gen_server:start_link(?MODULE, InitState, [{spawn_opt, [{message_queue_data, off_heap}]}]).

tick(Pid) -> gen_server:cast(Pid, tick).

wake(Pid) -> gen_server:cast(Pid, wake).

sleep(Pid, Reason) -> gen_server:cast(Pid, {sleep, Reason}).

apply_event(Pid, EventMap) -> gen_server:cast(Pid, {event, EventMap}).

get_state(Pid) -> gen_server:call(Pid, get_state, 5000).

set_policy(Pid, {Mod, Fun}) -> gen_server:call(Pid, {set_policy, Mod, Fun}).

%% ------------------------------------------------------------- gen_server --

init(Init) ->
    Id = maps:get(id, Init),
    WorldSeed = maps:get(world_seed, Init, 0),
    Rng = det_rng:new(WorldSeed, {agent, Id}),
    State = #{
        id => Id,
        region => maps:get(region, Init, undefined),
        civ_id => maps:get(civ_id, Init, undefined),
        archetype => maps:get(archetype, Init, <<"generic">>),
        name => maps:get(name, Init, Id),
        birth_tick => maps:get(birth_tick, Init, 0),
        activity => maps:get(activity, Init, active),
        location => maps:get(location, Init, {0, 0}),
        needs => maps:get(needs, Init, default_needs()),
        goals => maps:get(goals, Init, []),
        personality => maps:get(personality, Init, default_personality()),
        wealth => maps:get(wealth, Init, 0.0),
        skills => maps:get(skills, Init, #{}),
        beliefs => maps:get(beliefs, Init, #{}),
        relationships => maps:get(relationships, Init, #{}),
        memory => maps:get(memory, Init, []),
        policy => maps:get(policy, Init, undefined),
        rng => Rng,
        last_action => undefined,
        alive => true
    },
    {ok, State}.

handle_call(get_state, _From, State) ->
    {reply, {ok, sanitize(State)}, State};
handle_call({set_policy, Mod, Fun}, _From, State) ->
    {reply, ok, State#{policy => {Mod, Fun}}};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(tick, #{activity := dormant} = State) ->
    %% Dormant agents cost (almost) nothing: no decision, no need decay.
    {noreply, State};
handle_cast(tick, State) ->
    {noreply, do_tick(State)};
handle_cast(wake, State) ->
    {noreply, State#{activity => active}};
handle_cast({sleep, Reason}, State) ->
    NewState = remember(State, #{kind => went_dormant, reason => Reason}),
    {noreply, NewState#{activity => dormant}};
handle_cast({event, EventMap}, State) ->
    {noreply, integrate_event(State, EventMap)};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

%% ------------------------------------------------------------- internals --

default_needs() ->
    #{food => 1.0, water => 1.0, shelter => 1.0, safety => 1.0,
      income => 0.6, social => 0.6, status => 0.4, belonging => 0.6}.

default_personality() ->
    #{risk_aversion => 0.5, curiosity => 0.5, sociability => 0.5,
      patience => 0.5, ambition => 0.5, loyalty => 0.5, cooperation => 0.5,
      aggression => 0.2}.

decay_rate(shelter) -> 0.002;
decay_rate(safety) -> 0.003;
decay_rate(_) -> 0.01.

do_tick(State = #{needs := Needs, activity := Activity}) ->
    Factor = case Activity of sleeping -> 0.4; _ -> 1.0 end,
    DecayedNeeds = maps:map(
        fun(K, V) -> max(0.0, V - (decay_rate(K) * Factor)) end,
        Needs
    ),
    {Action, State2} = decide(State#{needs => DecayedNeeds}),
    apply_action_effects(Action, State2).

%% A custom policy only has to decide *what to do*: it receives a
%% sanitized read-only snapshot of the agent and must return a plain
%% action map. `agent_actor` itself remains the single source of truth
%% for state bookkeeping (needs, memory, rng advancement), so a buggy or
%% adversarial Lua script can influence what the agent chooses to do but
%% can never corrupt how state transitions are applied.
decide(State = #{policy := {Mod, Fun}}) when Mod =/= undefined ->
    try
        Action = Mod:Fun(sanitize(State)),
        true = is_map(Action),
        {Action, State}
    catch
        _:_ -> builtin_decide(State)
    end;
decide(State) ->
    builtin_decide(State).

%% Minimal fallback policy used when no Lua/Elixir policy is wired in:
%% address whichever need is currently most urgent.
builtin_decide(State = #{needs := Needs, rng := Rng}) ->
    {MostUrgent, _Val} = lists:foldl(
        fun({K, V}, {_BK, BV}) when V < BV -> {K, V};
           (_, Best) -> Best
        end,
        {undefined, 2.0},
        maps:to_list(Needs)
    ),
    {Roll, Rng2} = det_rng:roll(0.15, Rng),
    Action = #{type => satisfy_need, need => MostUrgent, exploratory => Roll},
    {Action, State#{rng => Rng2}}.

apply_action_effects(#{type := satisfy_need, need := Need} = Action, State)
        when Need =/= undefined ->
    Needs = maps:get(needs, State),
    NewNeeds = maps:update_with(Need, fun(V) -> min(1.0, V + 0.25) end, 0.25, Needs),
    remember(State#{needs => NewNeeds, last_action => Action}, #{kind => action, action => Action});
apply_action_effects(Action, State) ->
    State#{last_action => Action}.

integrate_event(State, EventMap) ->
    State1 = remember(State, EventMap#{kind => maps:get(kind, EventMap, external_event)}),
    case maps:get(relationship_delta, EventMap, undefined) of
        undefined -> State1;
        {WithWhom, Delta} -> bump_relationship(State1, WithWhom, Delta)
    end.

bump_relationship(State = #{relationships := Rels}, WithWhom, Delta) ->
    Cur = maps:get(WithWhom, Rels, 0.0),
    NewVal = max(-1.0, min(1.0, Cur + Delta)),
    Trimmed = case map_size(Rels) >= ?MAX_RELATIONSHIPS of
        true -> drop_weakest(Rels);
        false -> Rels
    end,
    State#{relationships => maps:put(WithWhom, NewVal, Trimmed)}.

drop_weakest(Rels) ->
    {WeakestKey, _} = lists:foldl(
        fun({K, V}, {_BK, BV}) when abs(V) < abs(BV) -> {K, V};
           (_, Best) -> Best
        end,
        {undefined, 2.0},
        maps:to_list(Rels)
    ),
    maps:remove(WeakestKey, Rels).

remember(State = #{memory := Memory}, Entry) ->
    Stamped = Entry#{t => erlang:system_time(millisecond)},
    Trimmed = lists:sublist([Stamped | Memory], ?MAX_MEMORY),
    State#{memory => Trimmed}.

%% Never leak the raw rng state or pid-bearing internals to callers.
sanitize(State) ->
    maps:without([rng], State).
