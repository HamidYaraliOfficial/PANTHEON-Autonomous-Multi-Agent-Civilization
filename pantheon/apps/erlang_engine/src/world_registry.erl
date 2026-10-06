%%%-------------------------------------------------------------------------
%%% @doc In-memory registry mapping logical ids (agent id, region id,
%%% institution id, ...) to the pid currently responsible for them.
%%%
%%% Backed by ETS so lookups from thousands of concurrently-ticking
%%% processes never have to serialize through a single gen_server call.
%%% Only writes (register/unregister) go through the gen_server, because
%%% ETS `public` write access from arbitrary processes is what causes the
%%% "who overwrote this" bugs distributed systems are famous for.
%%%-------------------------------------------------------------------------
-module(world_registry).
-behaviour(gen_server).

-export([start_link/0]).
-export([register_id/2, unregister_id/1, whereis_id/1, all_of_kind/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TAB, pantheon_registry).

%% ------------------------------------------------------------------ API --

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Kind :: agent | region | institution | organization | atom()
-spec register_id({Kind :: atom(), Id :: term()}, pid()) -> ok.
register_id(Key, Pid) ->
    gen_server:call(?MODULE, {register, Key, Pid}).

-spec unregister_id({atom(), term()}) -> ok.
unregister_id(Key) ->
    gen_server:call(?MODULE, {unregister, Key}).

-spec whereis_id({atom(), term()}) -> {ok, pid()} | error.
whereis_id(Key) ->
    case ets:lookup(?TAB, Key) of
        [{Key, Pid}] -> {ok, Pid};
        [] -> error
    end.

-spec all_of_kind(atom()) -> [{term(), pid()}].
all_of_kind(Kind) ->
    ets:foldl(
        fun
            ({{K, Id}, Pid}, Acc) when K =:= Kind -> [{Id, Pid} | Acc];
            (_, Acc) -> Acc
        end,
        [],
        ?TAB
    ).

%% ------------------------------------------------------------- gen_server --

init([]) ->
    _ = ets:new(?TAB, [named_table, protected, set, {read_concurrency, true}]),
    {ok, #{}}.

handle_call({register, Key, Pid}, _From, State) ->
    true = ets:insert(?TAB, {Key, Pid}),
    _ = erlang:monitor(process, Pid),
    {reply, ok, State#{Pid => Key}};
handle_call({unregister, Key}, _From, State) ->
    true = ets:delete(?TAB, Key),
    {reply, ok, State};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% Self-healing: if a registered process dies without unregistering
%% (crash, kill -9 equivalent), clean the ETS row automatically.
handle_info({'DOWN', _Ref, process, Pid, _Reason}, State) ->
    case maps:take(Pid, State) of
        {Key, NewState} ->
            ets:delete(?TAB, Key),
            {noreply, NewState};
        error ->
            {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
