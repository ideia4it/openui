defmodule OpenUI.Runtime.Collation do
  @moduledoc """
  String order for `@Sort`, close to the ICU root collation that ECMAScript's
  `localeCompare` uses (language.md, section 3.4).

  Strings compare first by their letters without accents or case, then by
  accents, then with lowercase before uppercase. This matches the root
  collation for letters, which is what the spec's fixtures check. Digits and
  punctuation keep code point order, unlike ICU.
  """

  @doc "Compares two strings."
  @spec compare(String.t(), String.t()) :: :lt | :eq | :gt
  def compare(left, right) do
    compare_keys(sort_key(left), sort_key(right))
  end

  defp sort_key(string) do
    decomposed = decompose(string)
    base = String.replace(decomposed, ~r/\p{Mn}/u, "")
    accents = Regex.scan(~r/\p{Mn}/u, decomposed) |> List.flatten()

    case_marks =
      for char <- String.graphemes(base), do: if(String.downcase(char) == char, do: 0, else: 1)

    [String.downcase(base), accents, case_marks, string]
  end

  # Text cut inside a multibyte character is not valid UTF-8; its valid part
  # decomposes and the stray bytes are dropped from the sort key.
  defp decompose(string) do
    case :unicode.characters_to_nfd_binary(string) do
      decomposed when is_binary(decomposed) -> decomposed
      {_error_or_incomplete, valid, _rest} -> valid
    end
  end

  defp compare_keys(left, right) when left < right, do: :lt
  defp compare_keys(left, right) when left > right, do: :gt
  defp compare_keys(_left, _right), do: :eq
end
