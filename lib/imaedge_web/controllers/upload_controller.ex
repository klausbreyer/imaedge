defmodule ImaedgeWeb.UploadController do
  use ImaedgeWeb, :controller

  alias Imaedge.Media
  alias Imaedge.Uploads

  def create(conn, %{"collection_id" => collection_id} = params) do
    collection = Media.get_collection_by_public_id!(collection_id)

    cond do
      not Uploads.allowed_mime?(params["mime"]) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "unsupported_mime", message: "Unsupported image format"})

      duplicate = Media.find_duplicate_image(collection, String.downcase(params["sha256"] || "")) ->
        json(conn, %{duplicate: true, image_id: duplicate.public_id})

      true ->
        attrs = %{
          "filename" => params["filename"],
          "mime" => params["mime"],
          "byte_size" => int_param(params["byte_size"]),
          "sha256" => params["sha256"],
          "contributor_id" => params["contributor_id"],
          "timezone_offset_minutes" => int_param(params["timezone_offset_minutes"])
        }

        case Media.create_upload_session(collection, attrs) do
          {:ok, session} ->
            json(conn, upload_json(collection, session))

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "invalid_upload", details: inspect(changeset.errors)})
        end
    end
  end

  def show(conn, %{"collection_id" => collection_id, "upload_id" => upload_id}) do
    collection = Media.get_collection_by_public_id!(collection_id)
    session = Media.get_upload_session!(collection, upload_id)

    json(conn, upload_json(collection, session))
  end

  def chunk(conn, %{"collection_id" => collection_id, "upload_id" => upload_id, "index" => index}) do
    collection = Media.get_collection_by_public_id!(collection_id)
    session = Media.get_upload_session!(collection, upload_id)

    with {index, ""} <- Integer.parse(index),
         {:ok, body, conn} <- read_chunk_body(conn, session.chunk_size),
         {:ok, result} <- Uploads.write_chunk(session, index, body) do
      json(conn, result)
    else
      {:more, _body, _conn} ->
        conn
        |> put_status(:request_entity_too_large)
        |> json(%{error: "chunk_too_large"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "chunk_failed", details: inspect(reason)})

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_chunk"})
    end
  end

  def finalize(conn, %{"collection_id" => collection_id, "upload_id" => upload_id}) do
    collection = Media.get_collection_by_public_id!(collection_id)
    session = Media.get_upload_session!(collection, upload_id)

    case Uploads.finalize(session) do
      {:ok, %{session: session, image: image, duplicate: true}} ->
        json(conn, %{duplicate: true, status: session.status, image_id: image.public_id})

      {:ok, %{session: session, image: image}} ->
        json(conn, %{status: session.status, image_id: image.public_id})

      {:error, {:missing_chunks, missing}} ->
        if duplicate = Media.find_duplicate_image(collection, session.sha256) do
          json(conn, %{duplicate: true, status: "done", image_id: duplicate.public_id})
        else
          conn
          |> put_status(:conflict)
          |> json(%{error: "missing_chunks", missing_chunks: missing})
        end

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "finalize_failed", details: inspect(reason)})
    end
  end

  def cancel(conn, %{"collection_id" => collection_id, "upload_id" => upload_id}) do
    collection = Media.get_collection_by_public_id!(collection_id)

    case Media.cancel_upload(collection, upload_id) do
      {:ok, session} ->
        :ok = Uploads.delete_temp(session)
        json(conn, %{status: "cancelled"})

      {:error, :already_accepted} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "already_accepted"})
    end
  end

  defp upload_json(collection, session) do
    duplicate = duplicate_image(collection, session)

    session
    |> session_json()
    |> maybe_put_duplicate(duplicate)
  end

  defp session_json(session) do
    %{
      id: session.public_id,
      status: session.status,
      chunk_size: session.chunk_size,
      total_chunks: session.total_chunks,
      missing_chunks: Uploads.missing_chunks(session),
      error_message: session.error_message
    }
  end

  defp duplicate_image(_collection, %{status: status}) when status in ["processing", "done"],
    do: nil

  defp duplicate_image(collection, session) do
    Media.find_duplicate_image(collection, session.sha256)
  end

  defp maybe_put_duplicate(json, nil), do: json

  defp maybe_put_duplicate(json, duplicate) do
    json
    |> Map.put(:duplicate, true)
    |> Map.put(:image_id, duplicate.public_id)
  end

  defp read_chunk_body(conn, chunk_size) do
    read_body(conn,
      length: chunk_size + 1024,
      read_length: chunk_size + 1024,
      read_timeout: upload_config(:chunk_read_timeout)
    )
  end

  defp upload_config(key) do
    :imaedge
    |> Application.fetch_env!(:uploads)
    |> Keyword.fetch!(key)
  end

  defp int_param(nil), do: nil
  defp int_param(value) when is_integer(value), do: value

  defp int_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
