defmodule Imaedge.Storage.Local do
  @moduledoc false

  def put_file(key, source_path, _opts \\ []) do
    target = local_path(key)
    File.mkdir_p!(Path.dirname(target))
    File.cp!(source_path, target)
    {:ok, public_url(key)}
  end

  def delete(key) do
    key
    |> local_path()
    |> File.rm()
    |> case do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def public_url(key) do
    public_path = config(:public_path)
    Path.join(public_path, key)
  end

  def local_path(key) do
    config(:root)
    |> Path.expand(File.cwd!())
    |> Path.join(key)
  end

  defp config(key) do
    :imaedge
    |> Application.fetch_env!(:object_storage)
    |> Keyword.fetch!(key)
  end
end
