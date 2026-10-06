%%%-------------------------------------------------------------------------
%%% @doc Deterministic random number generation.
%%%
%%% PANTHEON's reproducibility guarantee ("same world seed + same version
%%% => same history") depends on every actor drawing randomness from an
%%% independent, seed-derived stream instead of a shared global RNG (which
%%% would make outcomes depend on scheduling order — the number one enemy
%%% of deterministic replay in a concurrent system).
%%%
%%% Each stream is identified by `{WorldSeed, StreamId}` (StreamId is
%%% typically an agent id, a region id, or a subsystem name such as
%%% `weather` or `language_drift`). The stream's own state is kept in the
%%% *caller's* process dictionary-free state (returned explicitly), so two
%%% concurrent agents never race on the same generator.
%%%-------------------------------------------------------------------------
-module(det_rng).

-export([new/2, uniform/1, uniform_range/3, pick/2, roll/2, shuffle/2]).

-opaque stream() :: rand:state().
-export_type([stream/0]).

%% Derive an independent stream from the world seed + a stream id.
-spec new(integer(), term()) -> stream().
new(WorldSeed, StreamId) ->
    Hash = erlang:phash2({WorldSeed, StreamId}, 1 bsl 32),
    rand:seed_s(exsss, {Hash, Hash bxor 16#5DEECE66D, Hash bxor 16#B}).

%% Float in [0.0, 1.0) plus the advanced stream.
-spec uniform(stream()) -> {float(), stream()}.
uniform(Stream) ->
    rand:uniform_s(Stream).

%% Integer in [Low, High] inclusive.
-spec uniform_range(integer(), integer(), stream()) -> {integer(), stream()}.
uniform_range(Low, High, Stream) when High >= Low ->
    {F, Stream2} = rand:uniform_s(High - Low + 1, Stream),
    {Low + F - 1, Stream2}.

%% Pick one element from a non-empty list.
-spec pick([T], stream()) -> {T, stream()}.
pick(List, Stream) when List =/= [] ->
    {Idx, Stream2} = uniform_range(1, length(List), Stream),
    {lists:nth(Idx, List), Stream2}.

%% Bernoulli trial with probability P (0.0 - 1.0).
-spec roll(float(), stream()) -> {boolean(), stream()}.
roll(P, Stream) ->
    {V, Stream2} = uniform(Stream),
    {V < P, Stream2}.

%% Deterministic Fisher-Yates shuffle.
-spec shuffle([T], stream()) -> {[T], stream()}.
shuffle(List, Stream) ->
    shuffle(List, [], Stream).

shuffle([], Acc, Stream) ->
    {Acc, Stream};
shuffle(List, Acc, Stream) ->
    {Idx, Stream2} = uniform_range(1, length(List), Stream),
    Elem = lists:nth(Idx, List),
    Rest = lists:delete(Elem, List),
    shuffle(Rest, [Elem | Acc], Stream2).
