defmodule PantheonCore.LanguageTest do
  use ExUnit.Case

  setup do
    civ_id = "test-civ-#{System.unique_integer([:positive])}"
    {:ok, lang_id} = PantheonCore.Language.create_language(civ_id, 55)
    %{lang_id: lang_id}
  end

  test "coining a word for the same concept twice returns the same word", %{lang_id: lang_id} do
    {:ok, word1} = PantheonCore.Language.word_for(lang_id, :food, 0)
    {:ok, word2} = PantheonCore.Language.word_for(lang_id, :food, 10)
    assert word1 == word2
  end

  test "different concepts usually coin different words", %{lang_id: lang_id} do
    {:ok, food_word} = PantheonCore.Language.word_for(lang_id, :food, 0)
    {:ok, water_word} = PantheonCore.Language.word_for(lang_id, :water, 0)
    refute food_word == water_word
  end

  test "generate_name/2 returns a non-empty capitalized string", %{lang_id: lang_id} do
    {:ok, %{name: name}} = PantheonCore.Language.generate_name(lang_id, :city)
    assert String.length(name) > 0
    assert String.first(name) == String.upcase(String.first(name))
  end
end
