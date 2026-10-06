%%%-------------------------------------------------------------------------
%%% @doc Global event bus.
%%%
%%% Every meaningful thing that happens in the world (birth, death, trade,
%%% migration, discovery, law passed, war declared, word coined...) is
%%% published here as `{Topic, EventMap}`. Subscribers (the Elixir
%%% pantheon_core.History module, the WebSocket layer, plugins) receive
%%% `{pantheon_event, Topic, EventMap}` messages.
%%%
%%% This is intentionally a simple in-memory bus rather than a full
%%% Kafka-style log: PANTHEON's durable, replayable event log lives in
%%% `pantheon_core.History`, which subscribes to `all` and persists every
%%% event to the snapshot/event store. This module is just the wiring.
%%%-------------------------------------------------------------------------
-module(event_bus).
-behaviour(gen_server).

-export([start_link/0]).
-export([subscribe/1, subscribe/0, unsubscribe/1, publish/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% ------------------------------------------------------------------ API --

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Subscribe the calling process to a specific topic (atom) or `all`.
subscribe(Topic) ->
    gen_server:call(?MODULE, {subscribe, self(), Topic}).

subscribe() ->
    subscribe(all).

unsubscribe(Topic) ->
    gen_server:call(?MODULE, {unsubscribe, self(), Topic}).

%% Fire-and-forget publish. Never blocks the caller on subscriber speed.
-spec publish(atom(), map()) -> ok.
publish(Topic, EventMap) when is_atom(Topic), is_map(EventMap) ->
    gen_server:cast(?MODULE, {publish, Topic, EventMap}).

%% ------------------------------------------------------------- gen_server --

init([]) ->
    {ok, #{subs => #{}}}.

handle_call({subscribe, Pid, Topic}, _From, #{subs := Subs} = State) ->
    _ = erlang:monitor(process, Pid),
    Cur = maps:get(Topic, Subs, sets_new()),
    NewSubs = maps:put(Topic, sets_add(Pid, Cur), Subs),
    {reply, ok, State#{subs => NewSubs}};
handle_call({unsubscribe, Pid, Topic}, _From, #{subs := Subs} = State) ->
    Cur = maps:get(Topic, Subs, sets_new()),
    NewSubs = maps:put(Topic, sets_del(Pid, Cur), Subs),
    {reply, ok, State#{subs => NewSubs}}.

handle_cast({publish, Topic, EventMap}, #{subs := Subs} = State) ->
    Stamped = EventMap#{topic => Topic, bus_time => erlang:system_time(millisecond)},
    Direct = maps:get(Topic, Subs, sets_new()),
    All = maps:get(all, Subs, sets_new()),
    Targets = sets_union(Direct, All),
    lists:foreach(
        fun(Pid) -> Pid ! {pantheon_event, Topic, Stamped} end,
        sets_to_list(Targets)
    ),
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #{subs := Subs} = State) ->
    NewSubs = maps:map(fun(_Topic, Set) -> sets_del(Pid, Set) end, Subs),
    {noreply, State#{subs => NewSubs}};
handle_info(_Info, State) ->
    {noreply, State}.

%% Tiny helpers so we don't pull in the `sets` module's variable
%% (ordsets/sets) API inconsistencies across OTP versions.
sets_new() -> [].
sets_add(Pid, List) -> case lists:member(Pid, List) of true -> List; false -> [Pid | List] end.
sets_del(Pid, List) -> lists:delete(Pid, List).
sets_union(A, B) -> lists:usort(A ++ B).
sets_to_list(List) -> List.
