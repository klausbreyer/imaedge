defmodule Imaedge.Storage do
  @moduledoc false

  def put_file(key, source_path, opts \\ []) do
    adapter().put_file(key, source_path, opts)
  end

  def delete(key) when is_binary(key) do
    adapter().delete(key)
  end

  def fetch_to_temp(key) when is_binary(key) do
    adapter = adapter()

    cond do
      Code.ensure_loaded?(adapter) and function_exported?(adapter, :local_path, 1) ->
        {:ok, adapter.local_path(key)}

      Code.ensure_loaded?(adapter) and function_exported?(adapter, :fetch_to_temp, 1) ->
        adapter.fetch_to_temp(key)

      true ->
        :error
    end
  end

  def public_url(key) when is_binary(key) do
    adapter().public_url(key)
  end

  def local_path(key) when is_binary(key) do
    adapter = adapter()

    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :local_path, 1) do
      {:ok, adapter.local_path(key)}
    else
      :error
    end
  end

  defp adapter do
    :imaedge
    |> Application.fetch_env!(:object_storage)
    |> Keyword.fetch!(:adapter)
  end
end
