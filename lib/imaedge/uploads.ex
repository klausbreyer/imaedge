defmodule Imaedge.Uploads do
  @moduledoc false

  alias Imaedge.Id
  alias Imaedge.Media
  alias Imaedge.Media.UploadSession
  alias Imaedge.Repo
  alias Imaedge.Storage

  @allowed_mimes ~w(image/jpeg image/png image/webp)

  def allowed_mime?(mime), do: mime in @allowed_mimes

  def missing_chunks(%UploadSession{} = session) do
    present =
      session
      |> session_dir()
      |> Path.join("chunk_*")
      |> Path.wildcard()
      |> MapSet.new(&chunk_index_from_path/1)

    0..(session.total_chunks - 1)
    |> Enum.reject(&MapSet.member?(present, &1))
  end

  def write_chunk(%UploadSession{} = session, index, body)
      when is_integer(index) and index >= 0 and is_binary(body) do
    if index >= session.total_chunks do
      {:error, :chunk_out_of_range}
    else
      dir = session_dir(session)
      File.mkdir_p!(dir)

      path = chunk_path(session, index)
      File.write!(path, body)
      Media.update_upload_session(session, %{status: "uploading"})
      {:ok, %{missing_chunks: missing_chunks(session)}}
    end
  end

  def finalize(%UploadSession{} = session) do
    case missing_chunks(session) do
      [] -> do_finalize(session)
      missing -> {:error, {:missing_chunks, missing}}
    end
  end

  def delete_temp(%UploadSession{} = session) do
    session
    |> session_dir()
    |> File.rm_rf()
    |> case do
      {:ok, _} -> :ok
      {:error, _path, reason} -> {:error, reason}
    end
  end

  def assembled_path(%UploadSession{} = session) do
    Path.join(session_dir(session), "assembled")
  end

  defp do_finalize(%UploadSession{} = session) do
    with {:ok, session} <- Media.update_upload_session(session, %{status: "finalizing"}),
         assembled <- assemble!(session),
         {:ok, ^session} <- verify_hash(session, assembled),
         image_secret <- Id.base62(16),
         object_key <- original_object_key(session, image_secret),
         {:ok, original_url} <- Storage.put_file(object_key, assembled, cache: :original),
         {:ok, image} <-
           Media.create_processing_image(session, image_secret, object_key, original_url),
         {:ok, session} <-
           Media.update_upload_session(session, %{
             status: "processing",
             object_key: object_key,
             original_url: original_url,
             finalized_at: DateTime.utc_now(:microsecond)
           }),
         {:ok, _job} <-
           %{upload_session_id: session.id, image_id: image.id}
           |> Imaedge.Workers.IngestWorker.new()
           |> Oban.insert() do
      {:ok, %{session: session, image: image}}
    else
      {:error, reason} ->
        Media.fail_upload(session, reason)
        {:error, reason}
    end
  end

  defp assemble!(%UploadSession{} = session) do
    target = assembled_path(session)
    File.rm(target)

    output = File.open!(target, [:write, :binary])

    try do
      for index <- 0..(session.total_chunks - 1) do
        session
        |> chunk_path(index)
        |> File.stream!([], 64 * 1024)
        |> Enum.each(&IO.binwrite(output, &1))
      end
    after
      File.close(output)
    end

    target
  end

  defp verify_hash(%UploadSession{} = session, path) do
    hash =
      path
      |> File.stream!([], 64 * 1024)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    if hash == session.sha256 do
      {:ok, session}
    else
      {:error, :hash_mismatch}
    end
  end

  defp session_dir(%UploadSession{} = session) do
    collection = Repo.get!(Imaedge.Media.Collection, session.collection_id)

    :imaedge
    |> Application.fetch_env!(:uploads)
    |> Keyword.fetch!(:tmp_dir)
    |> Path.expand(File.cwd!())
    |> Path.join(collection.public_id)
    |> Path.join(session.public_id)
  end

  defp chunk_path(%UploadSession{} = session, index) do
    Path.join(session_dir(session), "chunk_#{index}")
  end

  defp chunk_index_from_path(path) do
    path
    |> Path.basename()
    |> String.replace_prefix("chunk_", "")
    |> String.to_integer()
  end

  defp original_object_key(%UploadSession{} = session, image_secret) do
    collection = Repo.get!(Imaedge.Media.Collection, session.collection_id)
    ext = extension_for(session)
    "collections/#{collection.public_id}/#{image_secret}/original#{ext}"
  end

  defp extension_for(%UploadSession{original_filename: filename, mime: mime}) do
    case {String.downcase(Path.extname(filename)), mime} do
      {ext, _} when ext in [".jpg", ".jpeg", ".png", ".webp"] -> ext
      {_, "image/jpeg"} -> ".jpg"
      {_, "image/png"} -> ".png"
      {_, "image/webp"} -> ".webp"
      _ -> ".bin"
    end
  end
end
