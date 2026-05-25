defmodule Imaedge.Id do
  @moduledoc false

  @alphabet String.to_charlist("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
  @slug_alphabet String.to_charlist("0123456789abcdefghijklmnopqrstuvwxyz")
  @base length(@alphabet)
  @slug_base length(@slug_alphabet)

  @place_modifiers ~w[
    alpine amber autumn basalt bright cedar coastal copper dawn drift dusky eastern fern
    foggy granite hidden hollow northern quiet silver southern sunlit tidal violet western
  ]

  @places ~w[
    avenue basin bridge canyon chapel courtyard dunes fjord fountain garden harbor island
    lagoon market meadow orchard overlook pier plaza quay ridge station terrace valley village
  ]

  @place_features ~w[
    arch beacon bend bluff cove crossing field gate grove landing lookout path point reef
    square spring trail wall wharf yard
  ]

  def base62(bytes \\ 16) when is_integer(bytes) and bytes > 0 do
    bytes
    |> :crypto.strong_rand_bytes()
    |> :binary.decode_unsigned()
    |> encode([])
  end

  def place_slug do
    [
      random(@place_modifiers),
      random(@places),
      random(@place_features),
      base36(6) |> String.pad_leading(10, "0")
    ]
    |> Enum.join("-")
  end

  defp encode(0, []), do: "0"
  defp encode(0, acc), do: acc |> Enum.reverse() |> List.to_string()

  defp encode(number, acc) do
    encode(div(number, @base), [Enum.at(@alphabet, rem(number, @base)) | acc])
  end

  defp base36(bytes) when is_integer(bytes) and bytes > 0 do
    bytes
    |> :crypto.strong_rand_bytes()
    |> :binary.decode_unsigned()
    |> encode_slug([])
  end

  defp encode_slug(0, []), do: "0"
  defp encode_slug(0, acc), do: acc |> Enum.reverse() |> List.to_string()

  defp encode_slug(number, acc) do
    encode_slug(div(number, @slug_base), [Enum.at(@slug_alphabet, rem(number, @slug_base)) | acc])
  end

  defp random(list) do
    Enum.random(list)
  end
end
