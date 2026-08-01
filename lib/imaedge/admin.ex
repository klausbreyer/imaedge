defmodule Imaedge.Admin do
  @moduledoc false

  import Ecto.Query

  alias Imaedge.Media.{Collection, Image, UploadSession}
  alias Imaedge.Repo

  @timezone "Europe/Berlin"
  @valid_days [30, 90, 365]

  def usage(params \\ %{}) do
    days = parse_days(Map.get(params, "days"))
    since = since(days)

    daily = daily_activity(since)
    collections = collection_usage()

    %{
      days: days,
      timezone: @timezone,
      summary: summary(),
      daily_activity: daily,
      storage_by_mime: storage_by_mime(),
      upload_statuses: upload_statuses(),
      image_statuses: image_statuses(),
      top_storage_collections: top_storage_collections(collections),
      recent_collections: recent_collections(collections),
      failed_collections: failed_collections(collections),
      failed_uploads: failed_uploads(),
      oban_states: oban_states(),
      oban_problem_jobs: oban_problem_jobs()
    }
  end

  def parse_days("all"), do: :all

  def parse_days(value) when is_binary(value) do
    case Integer.parse(value) do
      {days, ""} -> parse_days(days)
      _ -> 90
    end
  end

  def parse_days(value) when value in @valid_days, do: value
  def parse_days(_value), do: 90

  defp since(:all), do: nil
  defp since(days), do: DateTime.utc_now(:second) |> DateTime.add(-days, :day)

  defp summary do
    %{
      collections: Repo.aggregate(Collection, :count),
      accepted_images: accepted_images_count(),
      complete_images: count_images_with_status("complete"),
      processing_images: count_images_with_status("processing"),
      pending_delete_images: count_images_with_status("pending_delete"),
      deleted_images: count_images_with_status("deleted"),
      accepted_storage_bytes: accepted_storage_bytes(),
      upload_sessions: Repo.aggregate(UploadSession, :count),
      failed_uploads: count_uploads_with_status("failed"),
      active_upload_bytes: active_upload_bytes(),
      contributors: contributor_count()
    }
  end

  defp accepted_images_count do
    Image
    |> where([image], image.status != "deleted")
    |> Repo.aggregate(:count)
  end

  defp accepted_storage_bytes do
    Image
    |> where([image], image.status != "deleted")
    |> select([image], coalesce(sum(image.byte_size), 0))
    |> Repo.one()
  end

  defp active_upload_bytes do
    UploadSession
    |> where([upload], upload.status not in ["done", "duplicate", "cancelled"])
    |> select([upload], coalesce(sum(upload.byte_size), 0))
    |> Repo.one()
  end

  defp contributor_count do
    UploadSession
    |> select([upload], fragment("COUNT(DISTINCT ?)", upload.contributor_id))
    |> Repo.one()
  end

  defp count_images_with_status(status) do
    Image
    |> where([image], image.status == ^status)
    |> Repo.aggregate(:count)
  end

  defp count_uploads_with_status(status) do
    UploadSession
    |> where([upload], upload.status == ^status)
    |> Repo.aggregate(:count)
  end

  defp storage_by_mime do
    Image
    |> where([image], image.status != "deleted")
    |> group_by([image], image.mime)
    |> order_by([image], desc: coalesce(sum(image.byte_size), 0))
    |> select([image], %{
      mime: image.mime,
      images: count(image.id),
      bytes: coalesce(sum(image.byte_size), 0)
    })
    |> Repo.all()
  end

  defp upload_statuses do
    UploadSession
    |> group_by([upload], upload.status)
    |> order_by([upload], asc: upload.status)
    |> select([upload], %{
      status: upload.status,
      count: count(upload.id),
      bytes: coalesce(sum(upload.byte_size), 0)
    })
    |> Repo.all()
  end

  defp image_statuses do
    Image
    |> group_by([image], image.status)
    |> order_by([image], asc: image.status)
    |> select([image], %{
      status: image.status,
      count: count(image.id),
      bytes: coalesce(sum(image.byte_size), 0)
    })
    |> Repo.all()
  end

  defp daily_activity(since) do
    counts = %{
      new_collections: collection_count_by_day(since),
      uploads_started: upload_count_by_day(:inserted_at, since),
      uploads_finalized: upload_count_by_day(:finalized_at, since),
      images_accepted: image_count_by_day(:inserted_at, since),
      images_completed: completed_image_count_by_day(since),
      images_deleted: image_count_by_day(:deleted_at, since),
      accepted_bytes: image_bytes_by_day(since),
      active_collections: active_collections_by_day(since)
    }

    counts
    |> Enum.flat_map(fn {_key, values} -> Map.keys(values) end)
    |> Enum.uniq()
    |> Enum.sort(Date)
    |> Enum.reverse()
    |> Enum.map(fn date ->
      %{
        date: date,
        new_collections: Map.get(counts.new_collections, date, 0),
        uploads_started: Map.get(counts.uploads_started, date, 0),
        uploads_finalized: Map.get(counts.uploads_finalized, date, 0),
        images_accepted: Map.get(counts.images_accepted, date, 0),
        images_completed: Map.get(counts.images_completed, date, 0),
        images_deleted: Map.get(counts.images_deleted, date, 0),
        accepted_bytes: Map.get(counts.accepted_bytes, date, 0),
        active_collections: Map.get(counts.active_collections, date, 0)
      }
    end)
  end

  defp collection_count_by_day(since) do
    Collection
    |> maybe_since(:inserted_at, since)
    |> group_by(
      [collection],
      fragment("date(timezone('Europe/Berlin', ?))", collection.inserted_at)
    )
    |> select([collection], {
      fragment("date(timezone('Europe/Berlin', ?))", collection.inserted_at),
      count(collection.id)
    })
    |> Repo.all()
    |> Map.new()
  end

  defp upload_count_by_day(field, since) do
    UploadSession
    |> reject_nil(field)
    |> maybe_since(field, since)
    |> group_by([upload], fragment("date(timezone('Europe/Berlin', ?))", field(upload, ^field)))
    |> select([upload], {
      fragment("date(timezone('Europe/Berlin', ?))", field(upload, ^field)),
      count(upload.id)
    })
    |> Repo.all()
    |> Map.new()
  end

  defp image_count_by_day(field, since) do
    Image
    |> reject_nil(field)
    |> maybe_since(field, since)
    |> group_by([image], fragment("date(timezone('Europe/Berlin', ?))", field(image, ^field)))
    |> select([image], {
      fragment("date(timezone('Europe/Berlin', ?))", field(image, ^field)),
      count(image.id)
    })
    |> Repo.all()
    |> Map.new()
  end

  defp completed_image_count_by_day(since) do
    Image
    |> where([image], image.status == "complete")
    |> maybe_since(:updated_at, since)
    |> group_by([image], fragment("date(timezone('Europe/Berlin', ?))", image.updated_at))
    |> select([image], {
      fragment("date(timezone('Europe/Berlin', ?))", image.updated_at),
      count(image.id)
    })
    |> Repo.all()
    |> Map.new()
  end

  defp image_bytes_by_day(since) do
    Image
    |> where([image], image.status != "deleted")
    |> maybe_since(:inserted_at, since)
    |> group_by([image], fragment("date(timezone('Europe/Berlin', ?))", image.inserted_at))
    |> select([image], {
      fragment("date(timezone('Europe/Berlin', ?))", image.inserted_at),
      coalesce(sum(image.byte_size), 0)
    })
    |> Repo.all()
    |> Map.new()
  end

  defp active_collections_by_day(since) do
    []
    |> Kernel.++(collection_activity_rows(since))
    |> Kernel.++(upload_activity_rows(:inserted_at, since))
    |> Kernel.++(upload_activity_rows(:finalized_at, since))
    |> Kernel.++(image_activity_rows(:inserted_at, since))
    |> Kernel.++(image_activity_rows(:updated_at, since))
    |> Kernel.++(image_activity_rows(:deleted_at, since))
    |> Enum.reduce(%{}, fn {date, collection_id}, active ->
      Map.update(active, date, MapSet.new([collection_id]), &MapSet.put(&1, collection_id))
    end)
    |> Map.new(fn {date, collection_ids} -> {date, MapSet.size(collection_ids)} end)
  end

  defp collection_activity_rows(since) do
    Collection
    |> maybe_since(:inserted_at, since)
    |> select([collection], {
      fragment("date(timezone('Europe/Berlin', ?))", collection.inserted_at),
      collection.id
    })
    |> Repo.all()
  end

  defp upload_activity_rows(field, since) do
    UploadSession
    |> reject_nil(field)
    |> maybe_since(field, since)
    |> select([upload], {
      fragment("date(timezone('Europe/Berlin', ?))", field(upload, ^field)),
      upload.collection_id
    })
    |> Repo.all()
  end

  defp image_activity_rows(field, since) do
    Image
    |> reject_nil(field)
    |> maybe_since(field, since)
    |> select([image], {
      fragment("date(timezone('Europe/Berlin', ?))", field(image, ^field)),
      image.collection_id
    })
    |> Repo.all()
  end

  defp collection_usage do
    image_statuses = image_statuses_by_collection()
    upload_statuses = upload_statuses_by_collection()
    upload_totals = upload_totals_by_collection()
    image_activity = image_activity_by_collection()
    upload_activity = upload_activity_by_collection()

    Collection
    |> order_by([collection], desc: collection.updated_at)
    |> Repo.all()
    |> Enum.map(fn collection ->
      image_status = Map.get(image_statuses, collection.id, %{})
      upload_status = Map.get(upload_statuses, collection.id, %{})
      upload_total = Map.get(upload_totals, collection.id, %{})
      image_activity_dates = Map.get(image_activity, collection.id, %{})
      upload_activity_dates = Map.get(upload_activity, collection.id, %{})

      last_activity_at =
        [
          collection.updated_at,
          collection.inserted_at,
          image_activity_dates[:last_activity_at],
          upload_activity_dates[:last_activity_at]
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.max(DateTime, fn -> collection.inserted_at end)

      %{
        collection: collection,
        accepted_bytes: accepted_collection_bytes(image_status),
        image_count: sum_counts(image_status),
        complete_images: status_count(image_status, "complete"),
        processing_images: status_count(image_status, "processing"),
        pending_delete_images: status_count(image_status, "pending_delete"),
        deleted_images: status_count(image_status, "deleted"),
        upload_count: Map.get(upload_total, :upload_count, 0),
        failed_uploads: status_count(upload_status, "failed"),
        processing_uploads: status_count(upload_status, "processing"),
        active_uploads: active_upload_count(upload_status),
        contributor_count: Map.get(upload_total, :contributor_count, 0),
        top_contributor_share: Map.get(upload_total, :top_contributor_share, 0.0),
        first_activity_at:
          earliest_activity(collection, image_activity_dates, upload_activity_dates),
        last_activity_at: last_activity_at
      }
    end)
  end

  defp image_statuses_by_collection do
    Image
    |> group_by([image], [image.collection_id, image.status])
    |> select([image], %{
      collection_id: image.collection_id,
      status: image.status,
      count: count(image.id),
      bytes: coalesce(sum(image.byte_size), 0)
    })
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc ->
      Map.update(acc, row.collection_id, %{row.status => row}, &Map.put(&1, row.status, row))
    end)
  end

  defp upload_statuses_by_collection do
    UploadSession
    |> group_by([upload], [upload.collection_id, upload.status])
    |> select([upload], %{
      collection_id: upload.collection_id,
      status: upload.status,
      count: count(upload.id),
      bytes: coalesce(sum(upload.byte_size), 0)
    })
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc ->
      Map.update(acc, row.collection_id, %{row.status => row}, &Map.put(&1, row.status, row))
    end)
  end

  defp upload_totals_by_collection do
    totals =
      UploadSession
      |> group_by([upload], upload.collection_id)
      |> select([upload], %{
        collection_id: upload.collection_id,
        upload_count: count(upload.id),
        contributor_count: fragment("COUNT(DISTINCT ?)", upload.contributor_id)
      })
      |> Repo.all()
      |> Map.new(fn row -> {row.collection_id, Map.delete(row, :collection_id)} end)

    top_counts =
      UploadSession
      |> group_by([upload], [upload.collection_id, upload.contributor_id])
      |> select([upload], %{
        collection_id: upload.collection_id,
        count: count(upload.id)
      })
      |> Repo.all()
      |> Enum.group_by(& &1.collection_id, & &1.count)
      |> Map.new(fn {collection_id, counts} -> {collection_id, Enum.max(counts)} end)

    Map.new(totals, fn {collection_id, total} ->
      top_count = Map.get(top_counts, collection_id, 0)
      upload_count = total.upload_count

      share =
        case upload_count do
          0 -> 0.0
          _ -> top_count / upload_count
        end

      {collection_id, Map.put(total, :top_contributor_share, share)}
    end)
  end

  defp image_activity_by_collection do
    Image
    |> group_by([image], image.collection_id)
    |> select([image], %{
      collection_id: image.collection_id,
      first_activity_at: min(image.inserted_at),
      last_activity_at: max(image.updated_at)
    })
    |> Repo.all()
    |> Map.new(fn row -> {row.collection_id, Map.delete(row, :collection_id)} end)
  end

  defp upload_activity_by_collection do
    UploadSession
    |> group_by([upload], upload.collection_id)
    |> select([upload], %{
      collection_id: upload.collection_id,
      first_activity_at: min(upload.inserted_at),
      last_activity_at: max(upload.updated_at)
    })
    |> Repo.all()
    |> Map.new(fn row -> {row.collection_id, Map.delete(row, :collection_id)} end)
  end

  defp accepted_collection_bytes(image_status) do
    image_status
    |> Map.reject(fn {status, _row} -> status == "deleted" end)
    |> Enum.reduce(0, fn {_status, row}, bytes -> bytes + integer(row.bytes) end)
  end

  defp sum_counts(status_rows) do
    Enum.reduce(status_rows, 0, fn {_status, row}, count -> count + row.count end)
  end

  defp status_count(status_rows, status), do: get_in(status_rows, [status, :count]) || 0

  defp active_upload_count(status_rows) do
    status_rows
    |> Map.drop(["done", "duplicate", "cancelled"])
    |> sum_counts()
  end

  defp earliest_activity(collection, image_activity, upload_activity) do
    [
      collection.inserted_at,
      image_activity[:first_activity_at],
      upload_activity[:first_activity_at]
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.min(DateTime, fn -> collection.inserted_at end)
  end

  defp top_storage_collections(collections) do
    collections
    |> Enum.sort_by(&{&1.accepted_bytes, timestamp(&1.last_activity_at)}, :desc)
    |> Enum.take(20)
  end

  defp recent_collections(collections) do
    collections
    |> Enum.sort_by(&timestamp(&1.last_activity_at), :desc)
    |> Enum.take(20)
  end

  defp failed_collections(collections) do
    collections
    |> Enum.filter(
      &(&1.failed_uploads > 0 or &1.processing_images > 0 or &1.processing_uploads > 0)
    )
    |> Enum.sort_by(
      &{&1.failed_uploads, &1.processing_images, timestamp(&1.last_activity_at)},
      :desc
    )
    |> Enum.take(20)
  end

  defp failed_uploads do
    UploadSession
    |> join(:inner, [upload], collection in assoc(upload, :collection))
    |> where([upload, _collection], upload.status == "failed")
    |> order_by([upload, _collection], desc: upload.updated_at)
    |> limit(20)
    |> select([upload, collection], %{
      collection_public_id: collection.public_id,
      collection_name: collection.name,
      status: upload.status,
      byte_size: upload.byte_size,
      updated_at: upload.updated_at,
      error_message: upload.error_message
    })
    |> Repo.all()
  end

  defp oban_states do
    Oban.Job
    |> group_by([job], job.state)
    |> order_by([job], asc: job.state)
    |> select([job], %{state: job.state, count: count(job.id)})
    |> Repo.all()
  end

  defp oban_problem_jobs do
    Oban.Job
    |> where([job], job.state in ["retryable", "cancelled", "discarded"])
    |> order_by([job], desc: coalesce(job.attempted_at, job.scheduled_at))
    |> limit(10)
    |> select([job], %{
      state: job.state,
      worker: job.worker,
      attempt: job.attempt,
      max_attempts: job.max_attempts,
      attempted_at: job.attempted_at,
      scheduled_at: job.scheduled_at
    })
    |> Repo.all()
  end

  defp maybe_since(query, _field, nil), do: query

  defp maybe_since(query, field, since) do
    where(query, [row], field(row, ^field) >= ^since)
  end

  defp reject_nil(query, field) do
    where(query, [row], not is_nil(field(row, ^field)))
  end

  defp integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp integer(value), do: value || 0

  defp timestamp(nil), do: 0
  defp timestamp(datetime), do: DateTime.to_unix(datetime, :microsecond)
end
