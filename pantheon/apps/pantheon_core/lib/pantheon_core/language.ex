defmodule PantheonCore.Language do
  @moduledoc """
  Synthetic Language Evolution Engine.

  Each civilization is seeded with its own phoneme inventory and syllable
  patterns. Words are coined on demand for concepts agents actually need
  to talk about (food, trade, family, danger...), and every word carries
  an origin: who/what coined it, on which tick, and — as `drift/1` runs —
  a full mutation history, so the Language Evolution Viewer described in
  the design can show a word's shape changing across generations.

  This is a deliberately compact model of the much larger "Language
  Evolution Engine" described in the original brief (no full generative
  grammar, no phonotactic rule engine) — it is meant to be a genuine,
  extensible starting point rather than a facade.
  """
  use GenServer

  @consonants ~w(k t p b d g m n s z r l v f h sh th ng)
  @vowels ~w(a e i o u ai au)
  @name_kinds [:person, :civilization, :city, :river, :organization]

  # ---------------------------------------------------------------- API --

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Create a brand new synthetic language for a civilization."
  def create_language(civ_id, world_seed) do
    GenServer.call(__MODULE__, {:create, civ_id, world_seed})
  end

  @doc "Get (or coin, if unseen) the word for a concept in a language."
  def word_for(lang_id, concept, tick \\ 0) do
    GenServer.call(__MODULE__, {:word_for, lang_id, concept, tick})
  end

  @doc "Generate a plausible proper name in this language (person/city/civ/...)."
  def generate_name(lang_id, kind \\ :person) when kind in @name_kinds do
    GenServer.call(__MODULE__, {:name, lang_id, kind})
  end

  @doc "Run one step of language drift: a random existing word mutates slightly."
  def drift(lang_id, tick) do
    GenServer.cast(__MODULE__, {:drift, lang_id, tick})
  end

  def get_language(lang_id), do: GenServer.call(__MODULE__, {:get, lang_id})

  def list_languages, do: GenServer.call(__MODULE__, :list)

  # ----------------------------------------------------------- callbacks --

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:create, civ_id, world_seed}, _from, state) do
    lang_id = "lang-#{civ_id}"
    rng = PantheonCore.RNG.new(world_seed, {:language, civ_id})
    {cons_count, rng} = PantheonCore.RNG.range(6, length(@consonants), rng)
    {vow_count, rng} = PantheonCore.RNG.range(3, length(@vowels), rng)
    {consonants, rng} = PantheonCore.RNG.shuffle(@consonants, rng)
    {vowels, rng} = PantheonCore.RNG.shuffle(@vowels, rng)

    lang = %{
      id: lang_id,
      civ_id: civ_id,
      consonants: Enum.take(consonants, cons_count),
      vowels: Enum.take(vowels, vow_count),
      syllable_patterns: [:cv, :cvc, :vc, :cvcv],
      lexicon: %{},
      history: [],
      rng: rng
    }

    {:reply, {:ok, lang_id}, Map.put(state, lang_id, lang)}
  end

  def handle_call({:word_for, lang_id, concept, tick}, _from, state) do
    with {:ok, lang} <- fetch(state, lang_id) do
      case Map.get(lang.lexicon, concept) do
        nil ->
          {word, lang2} = coin_word(lang, concept, tick, :need)
          {:reply, {:ok, word}, Map.put(state, lang_id, lang2)}

        entry ->
          {:reply, {:ok, entry.word}, state}
      end
    else
      :error -> {:reply, {:error, :unknown_language}, state}
    end
  end

  def handle_call({:name, lang_id, kind}, _from, state) do
    with {:ok, lang} <- fetch(state, lang_id) do
      {name, rng2} = build_word(lang, 2..3)
      capitalized = String.capitalize(name)
      {:reply, {:ok, %{kind: kind, name: capitalized}}, put_in(state[lang_id].rng, rng2)}
    else
      :error -> {:reply, {:error, :unknown_language}, state}
    end
  end

  def handle_call({:get, lang_id}, _from, state) do
    {:reply, Map.fetch(state, lang_id), state}
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.keys(state), state}
  end

  @impl true
  def handle_cast({:drift, lang_id, tick}, state) do
    case Map.get(state, lang_id) do
      nil ->
        {:noreply, state}

      lang when map_size(lang.lexicon) == 0 ->
        {:noreply, state}

      lang ->
        {concept, rng} = PantheonCore.RNG.pick(Map.keys(lang.lexicon), lang.rng)
        entry = Map.fetch!(lang.lexicon, concept)
        {mutated, rng} = mutate_word(lang, entry.word, rng)

        change = %{
          concept: concept,
          from: entry.word,
          to: mutated,
          tick: tick,
          reason: "sound_change"
        }

        new_entry = %{entry | word: mutated, history: [change | entry.history]}
        lang2 = %{
          lang
          | lexicon: Map.put(lang.lexicon, concept, new_entry),
            history: [change | lang.history],
            rng: rng
        }

        {:noreply, Map.put(state, lang_id, lang2)}
    end
  end

  # ------------------------------------------------------------ internal --

  defp fetch(state, lang_id) do
    case Map.fetch(state, lang_id) do
      {:ok, lang} -> {:ok, lang}
      :error -> :error
    end
  end

  defp coin_word(lang, concept, tick, reason) do
    {word, rng2} = build_word(lang, 1..3)

    entry = %{
      word: word,
      concept: concept,
      first_seen_tick: tick,
      origin_reason: reason,
      history: []
    }

    lang2 = %{lang | lexicon: Map.put(lang.lexicon, concept, entry), rng: rng2}
    {word, lang2}
  end

  defp build_word(lang, syllable_range) do
    {n_syl, rng} = PantheonCore.RNG.range(Enum.min(syllable_range), Enum.max(syllable_range), lang.rng)

    {syllables, rng} =
      Enum.map_reduce(1..n_syl, rng, fn _, r ->
        {pattern, r} = PantheonCore.RNG.pick(lang.syllable_patterns, r)
        build_syllable(lang, pattern, r)
      end)

    {Enum.join(syllables), rng}
  end

  defp build_syllable(lang, pattern, rng) do
    pattern
    |> Atom.to_string()
    |> String.graphemes()
    |> Enum.map_reduce(rng, fn
      "c", r -> PantheonCore.RNG.pick(lang.consonants, r)
      "v", r -> PantheonCore.RNG.pick(lang.vowels, r)
    end)
    |> then(fn {parts, r} -> {Enum.join(parts), r} end)
  end

  # A "sound change": replace one phoneme in the word with a phonetically
  # adjacent one, or drop a phoneme — the two most common real diachronic
  # sound-change shapes, kept intentionally simple.
  defp mutate_word(lang, word, rng) do
    graphemes = String.graphemes(word)
    {idx, rng} = PantheonCore.RNG.range(0, max(length(graphemes) - 1, 0), rng)
    {mode, rng} = PantheonCore.RNG.pick([:swap, :drop], rng)

    case mode do
      :drop when length(graphemes) > 2 ->
        {List.delete_at(graphemes, idx) |> Enum.join(), rng}

      _ ->
        {replacement, rng} =
          if String.match?(Enum.at(graphemes, idx, ""), ~r/[aeiou]/) do
            PantheonCore.RNG.pick(lang.vowels, rng)
          else
            PantheonCore.RNG.pick(lang.consonants, rng)
          end

        {List.replace_at(graphemes, idx, replacement) |> Enum.join(), rng}
    end
  end
end
