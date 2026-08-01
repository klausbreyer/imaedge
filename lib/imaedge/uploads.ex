defmodule Imaedge.Uploads do
  @moduledoc false

  require Logger

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

  def write_chunk(%UploadSession{status: status}, _index, _body)
      when status in ["processing", "done"] do
    {:ok, %{missing_chunks: []}}
  end

  def write_chunk(%UploadSession{status: "cancelled"}, _index, _body),
    do: {:error, :cancelled}

  def write_chunk(%UploadSession{} = session, index, body)
      when is_integer(index) and index >= 0 and is_binary(body) do
    if index >= session.total_chunks do
      {:error, :chunk_out_of_range}
    else
      dir = session_dir(session)
      File.mkdir_p!(dir)

      path = chunk_path(session, index)
      File.write!(path, body)

      case Media.mark_uploading(session) do
        {:ok, session} ->
          {:ok, %{missing_chunks: missing_chunks(session)}}

        {:error, :cancelled} = error ->
          delete_temp(session)
          error

        {:error, :already_accepted} ->
          {:ok, %{missing_chunks: []}}
      end
    end
  end

  def finalize(%UploadSession{status: "cancelled"}), do: {:error, :cancelled}

  def finalize(%UploadSession{status: status, object_key: object_key} = session)
      when status in ["processing", "done"] and not is_nil(object_key) do
    image = Repo.get_by(Imaedge.Media.Image, upload_session_id: session.id)

    if image do
      {:ok, session} = Media.update_upload_session(session, %{error_message: nil})
      {:ok, %{session: session, image: image}}
    else
      do_finalize(session)
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
           insert_processing_image(session, image_secret, object_key, original_url),
         {:ok, session} <-
           Media.update_upload_session(session, %{
             status: "processing",
             object_key: object_key,
             original_url: original_url,
             error_message: nil,
             finalized_at: DateTime.utc_now(:microsecond)
           }),
         {:ok, _job} <-
           %{upload_session_id: session.id, image_id: image.id}
           |> Imaedge.Workers.IngestWorker.new()
           |> Oban.insert() do
      {:ok, %{session: session, image: image}}
    else
      {:duplicate, existing_image, orphan_key} ->
        # Race: another upload landed the same SHA256 first. Drop the
        # original we just put in Tigris and resolve as a duplicate.
        Logger.info(
          "finalize duplicate resolved session=#{session.public_id} sha256=#{session.sha256} existing_image=#{existing_image.public_id}"
        )

        if orphan_key, do: Storage.delete(orphan_key)

        collection = Repo.get!(Imaedge.Media.Collection, session.collection_id)

        {:ok, session} =
          Media.update_upload_session(session, %{
            status: "done",
            error_message: nil,
            finalized_at: DateTime.utc_now(:microsecond)
          })

        Media.broadcast(collection, {:upload_changed, session})
        {:ok, %{session: session, image: existing_image, duplicate: true}}

      {:error, reason} ->
        Logger.warning(
          "finalize failed session=#{session.public_id} sha256=#{session.sha256} reason=#{inspect(reason)}"
        )

        Media.fail_upload(session, reason)
        {:error, reason}
    end
  end

  defp insert_processing_image(session, image_secret, object_key, original_url) do
    case Media.create_processing_image(session, image_secret, object_key, original_url) do
      {:ok, image} ->
        {:ok, image}

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :sha256) do
          case existing_image_for_sha256(session) do
            nil -> error
            existing -> {:duplicate, existing, object_key}
          end
        else
          error
        end
    end
  end

  defp existing_image_for_sha256(%UploadSession{} = session) do
    # Mirrors the unique index "WHERE deleted_at IS NULL" so we always find
    # the row that caused the constraint violation, regardless of status.
    import Ecto.Query

    Imaedge.Media.Image
    |> where([image], image.collection_id == ^session.collection_id)
    |> where([image], image.sha256 == ^session.sha256)
    |> where([image], is_nil(image.deleted_at))
    |> order_by([image], asc: image.id)
    |> limit(1)
    |> Repo.one()
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
