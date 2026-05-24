defmodule Imaedge.Id do
  @moduledoc false

  @alphabet String.to_charlist("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
  @base length(@alphabet)

  def base62(bytes \\ 16) when is_integer(bytes) and bytes > 0 do
    bytes
    |> :crypto.strong_rand_bytes()
    |> :binary.decode_unsigned()
    |> encode([])
  end

  defp encode(0, []), do: "0"
  defp encode(0, acc), do: acc |> Enum.reverse() |> List.to_string()

  defp encode(number, acc) do
    encode(div(number, @base), [Enum.at(@alphabet, rem(number, @base)) | acc])
  end
end
