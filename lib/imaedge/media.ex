defmodule Imaedge.Media do
  @moduledoc false

  import Ecto.Query
  alias Imaedge.Id
  alias Imaedge.Media.{Collection, Image, UploadSession}
  alias Imaedge.Repo
  alias Imaedge.Storage

  @topic_prefix "collection:"
  @rebalance_step_microseconds 1_000_000

  def create_collection do
    %Collection{}
    |> Collection.changeset(%{public_id: Id.base62(20)})
    |> Repo.insert()
  end

  def get_collection_by_public_id(public_id) do
    Repo.get_by(Collection, public_id: public_id)
  end

  def get_collection_by_public_id!(public_id) do
    Repo.get_by!(Collection, public_id: public_id)
  end

  def list_gallery_images(%Collection{} = collection) do
    Image
    |> where([image], image.collection_id == ^collection.id)
    |> where([image], image.status == "complete")
    |> where([image], is_nil(image.deleted_at))
    |> order_by([image], asc: image.effective_taken_at, asc: image.id)
    |> Repo.all()
  end

  def list_visible_uploads(%Collection{} = collection) do
    UploadSession
    |> where([upload], upload.collection_id == ^collection.id)
    |> where(
      [upload],
      upload.status in ["created", "uploading", "finalizing", "processing", "failed"]
    )
    |> order_by([upload], desc: upload.updated_at)
    |> Repo.all()
  end

  def find_duplicate_image(%Collection{} = collection, sha256) do
    Image
    |> where([image], image.collection_id == ^collection.id)
    |> where([image], image.sha256 == ^sha256)
    |> where([image], image.status in ["processing", "complete"])
    |> where([image], is_nil(image.deleted_at))
    |> Repo.one()
  end

  def create_upload_session(%Collection{} = collection, attrs) do
    chunk_size = upload_config(:chunk_size)
    byte_size = Map.fetch!(attrs, "byte_size")
    total_chunks = max(1, ceil(byte_size / chunk_size))

    params = %{
      public_id: Id.base62(16),
      collection_id: collection.id,
      contributor_id: Map.fetch!(attrs, "contributor_id"),
      original_filename: sanitize_filename(Map.fetch!(attrs, "filename")),
      mime: Map.fetch!(attrs, "mime"),
      byte_size: byte_size,
      sha256: String.downcase(Map.fetch!(attrs, "sha256")),
      timezone_offset_minutes: Map.get(attrs, "timezone_offset_minutes"),
      chunk_size: chunk_size,
      total_chunks: total_chunks,
      status: "created"
    }

    %UploadSession{}
    |> UploadSession.changeset(params)
    |> Repo.insert()
    |> tap(fn
      {:ok, session} -> broadcast(collection, {:upload_changed, session})
      _ -> :ok
    end)
  end

  def get_upload_session!(%Collection{} = collection, public_id) do
    Repo.get_by!(UploadSession, collection_id: collection.id, public_id: public_id)
  end

  def update_upload_session(%UploadSession{} = session, attrs) do
    session
    |> UploadSession.changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, session} ->
        collection = Repo.get!(Collection, session.collection_id)
        broadcast(collection, {:upload_changed, session})

      _ ->
        :ok
    end)
  end

  def create_processing_image(%UploadSession{} = session, image_secret, object_key, original_url) do
    collection = Repo.get!(Collection, session.collection_id)
    now = DateTime.utc_now(:microsecond)

    params = %{
      public_id: Id.base62(16),
      image_secret: image_secret,
      collection_id: collection.id,
      upload_session_id: session.id,
      contributor_id: session.contributor_id,
      original_filename: session.original_filename,
      mime: session.mime,
      byte_size: session.byte_size,
      sha256: session.sha256,
      original_key: object_key,
      original_url: original_url,
      effective_taken_at: now,
      time_source: "upload_time",
      status: "processing"
    }

    %Image{}
    |> Image.changeset(params)
    |> Repo.insert()
    |> tap(fn
      {:ok, image} -> broadcast(collection, {:image_changed, image})
      _ -> :ok
    end)
  end

  def complete_image(%Image{} = image, attrs) do
    image
    |> Image.changeset(Map.put(attrs, :status, "complete"))
    |> Repo.update()
    |> tap(fn
      {:ok, image} ->
        collection = Repo.get!(Collection, image.collection_id)
        broadcast(collection, {:image_changed, image})

      _ ->
        :ok
    end)
  end

  def fail_upload(%UploadSession{} = session, message) do
    update_upload_session(session, %{status: "failed", error_message: inspect_message(message)})
  end

  def retry_failed_upload(%Collection{} = collection, upload_public_id) do
    session = get_upload_session!(collection, upload_public_id)

    with {:ok, session} <-
           update_upload_session(session, %{status: "processing", error_message: nil}),
         {:ok, _job} <-
           %{upload_session_id: session.id} |> Imaedge.Workers.IngestWorker.new() |> Oban.insert() do
      {:ok, session}
    end
  end

  def remove_failed_upload(%Collection{} = collection, upload_public_id) do
    session = get_upload_session!(collection, upload_public_id)

    Repo.transaction(fn ->
      delete_session_objects(session)
      Repo.delete!(session)
    end)
    |> tap(fn _ -> broadcast(collection, {:collection_changed, collection.public_id}) end)
  end

  def move_image(%Collection{} = collection, image_public_id, direction)
      when direction in ["earlier", "later"] do
    images = list_gallery_images(collection)
    index = Enum.find_index(images, &(&1.public_id == image_public_id))

    with index when is_integer(index) <- index,
         image <- Enum.at(images, index),
         {:ok, image} <- move_image_at(collection, images, image, index, direction) do
      broadcast(collection, {:images_reordered, collection.public_id})
      {:ok, image}
    else
      nil -> {:error, :not_found}
      :edge -> {:error, :edge}
      error -> error
    end
  end

  def update_effective_time(%Collection{} = collection, image_public_id, iso_datetime) do
    with image when not is_nil(image) <-
           Repo.get_by(Image, collection_id: collection.id, public_id: image_public_id),
         {:ok, datetime} <- parse_album_datetime(iso_datetime, image.timezone_offset_minutes),
         {:ok, image} <- Image.changeset(image, %{effective_taken_at: datetime}) |> Repo.update() do
      broadcast(collection, {:image_changed, image})
      {:ok, image}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def mark_pending_delete(%Collection{} = collection, image_public_id) do
    with image when not is_nil(image) <-
           Repo.get_by(Image, collection_id: collection.id, public_id: image_public_id),
         delete_after <- DateTime.add(DateTime.utc_now(:microsecond), 10, :second),
         {:ok, image} <-
           Image.changeset(image, %{status: "pending_delete", delete_after: delete_after})
           |> Repo.update() do
      broadcast(collection, {:image_deleted, image})
      schedule_hard_delete(image.id, delete_after)
      {:ok, image}
    else
      nil -> {:error, :not_found}
    end
  end

  def undo_delete(%Collection{} = collection, image_public_id) do
    with image when not is_nil(image) <-
           Repo.get_by(Image,
             collection_id: collection.id,
             public_id: image_public_id,
             status: "pending_delete"
           ),
         {:ok, image} <-
           Image.changeset(image, %{status: "complete", delete_after: nil}) |> Repo.update() do
      broadcast(collection, {:image_changed, image})
      {:ok, image}
    else
      nil -> {:error, :not_found}
    end
  end

  def hard_delete_due_image(image_id) do
    now = DateTime.utc_now(:microsecond)

    Repo.transaction(fn ->
      image = Repo.get!(Image, image_id)

      if image.status == "pending_delete" and DateTime.compare(image.delete_after, now) != :gt do
        delete_image_objects(image)

        image
        |> Image.changeset(%{status: "deleted", deleted_at: now})
        |> Repo.update!()
      else
        image
      end
    end)
  end

  def subscribe(%Collection{} = collection) do
    Phoenix.PubSub.subscribe(Imaedge.PubSub, topic(collection))
  end

  def broadcast(%Collection{} = collection, message) do
    Phoenix.PubSub.broadcast(Imaedge.PubSub, topic(collection), message)
  end

  def topic(%Collection{public_id: public_id}), do: @topic_prefix <> public_id

  def upload_config(key) do
    :imaedge
    |> Application.fetch_env!(:uploads)
    |> Keyword.fetch!(key)
  end

  def sanitize_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9._ -]/, "_")
    |> String.slice(0, 120)
    |> case do
      "" -> "image"
      value -> value
    end
  end

  defp move_image_at(collection, images, image, index, direction) do
    case shifted_time(images, index, direction) do
      {:ok, {:time, new_time}} ->
        Image.changeset(image, %{effective_taken_at: new_time}) |> Repo.update()

      {:ok, {:rebalance, reordered_images}} ->
        rebalance_images(collection, reordered_images, image.public_id)

      other ->
        other
    end
  end

  defp shifted_time(images, index, "earlier") when index <= 0 or length(images) <= 1, do: :edge

  defp shifted_time(images, index, "earlier") do
    right = Enum.at(images, index - 1).effective_taken_at

    left =
      case Enum.at(images, index - 2) do
        nil -> DateTime.add(right, -1_000_000, :microsecond)
        image -> image.effective_taken_at
      end

    midpoint_or_rebalance(left, right, images, index, index - 1)
  end

  defp shifted_time(images, index, "later") when index >= length(images) - 1, do: :edge

  defp shifted_time(images, index, "later") do
    left = Enum.at(images, index + 1).effective_taken_at

    right =
      case Enum.at(images, index + 2) do
        nil -> DateTime.add(left, 1_000_000, :microsecond)
        image -> image.effective_taken_at
      end

    midpoint_or_rebalance(left, right, images, index, index + 1)
  end

  defp midpoint_or_rebalance(left, right, images, index, new_index) do
    case midpoint(left, right) do
      {:ok, time} -> {:ok, {:time, time}}
      :no_space -> {:ok, {:rebalance, move_in_list(images, index, new_index)}}
    end
  end

  defp midpoint(left, right) do
    diff = DateTime.diff(right, left, :microsecond)

    if diff > 1 do
      {:ok, DateTime.add(left, div(diff, 2), :microsecond)}
    else
      :no_space
    end
  end

  defp move_in_list(items, index, new_index) do
    item = Enum.at(items, index)

    items
    |> List.delete_at(index)
    |> List.insert_at(new_index, item)
  end

  defp rebalance_images(_collection, images, moved_public_id) do
    base = earliest_time(images)

    Repo.transaction(fn ->
      images
      |> Enum.with_index()
      |> Enum.map(fn {image, index} ->
        new_time = DateTime.add(base, index * @rebalance_step_microseconds, :microsecond)
        image |> Image.changeset(%{effective_taken_at: new_time}) |> Repo.update!()
      end)
    end)
    |> case do
      {:ok, images} -> {:ok, Enum.find(images, &(&1.public_id == moved_public_id))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp earliest_time([image | images]) do
    Enum.reduce(images, image.effective_taken_at, fn image, earliest ->
      case DateTime.compare(image.effective_taken_at, earliest) do
        :lt -> image.effective_taken_at
        _other -> earliest
      end
    end)
  end

  defp parse_album_datetime(value, offset_minutes) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, _reason} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive_datetime} -> {:ok, naive_to_utc(naive_datetime, offset_minutes)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp naive_to_utc(naive_datetime, offset_minutes) when is_integer(offset_minutes) do
    naive_datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.add(-offset_minutes * 60, :second)
  end

  defp naive_to_utc(naive_datetime, _offset_minutes),
    do: DateTime.from_naive!(naive_datetime, "Etc/UTC")

  defp schedule_hard_delete(image_id, delete_after) do
    delay = max(DateTime.diff(delete_after, DateTime.utc_now(:microsecond), :millisecond), 0)

    Task.start(fn ->
      Process.sleep(delay)
      hard_delete_due_image(image_id)
    end)
  end

  defp delete_session_objects(%UploadSession{} = session) do
    if session.object_key do
      Storage.delete(session.object_key)
    end
  end

  defp delete_image_objects(%Image{} = image) do
    [image.original_key, image.preview_small_key, image.preview_large_key]
    |> Enum.reject(&is_nil/1)
    |> Enum.each(&Storage.delete/1)
  end

  defp inspect_message(%{message: message}) when is_binary(message), do: message
  defp inspect_message(message) when is_binary(message), do: message
  defp inspect_message(message), do: inspect(message)
end
