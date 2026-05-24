defmodule Imaedge.Workers.IngestWorker do
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias Imaedge.Media
  alias Imaedge.Media.{Image, UploadSession}
  alias Imaedge.Repo
  alias Imaedge.Storage
  alias Imaedge.Uploads

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    session = Repo.get!(UploadSession, args["upload_session_id"])
    image = image_for(args, session)

    case safe_ingest(session, image) do
      {:ok, _image} ->
        Uploads.delete_temp(session)
        Media.update_upload_session(session, %{status: "done", error_message: nil})
        :ok

      {:error, reason} when attempt >= max_attempts ->
        Uploads.delete_temp(session)
        Media.fail_upload(session, reason)
        :discard

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp safe_ingest(session, image) do
    ingest(session, image)
  rescue
    exception -> {:error, Exception.format(:error, exception, __STACKTRACE__)}
  catch
    kind, reason -> {:error, Exception.format(kind, reason, __STACKTRACE__)}
  end

  defp ingest(%UploadSession{} = session, %Image{} = image) do
    with {:ok, original_path} <- original_path(image),
         {:ok, loaded} <- open_autorotated(original_path),
         {width, height, _bands} <- Elixir.Image.shape(loaded),
         exif <- read_exif(original_path),
         timestamps <- timestamps(exif, session),
         {:ok, small_path} <- preview(original_path, 480, 70),
         {:ok, large_path} <- preview(original_path, 1600, 82),
         small_key <- preview_key(image, "preview-small.webp"),
         large_key <- preview_key(image, "preview-large.webp"),
         {:ok, small_url} <- Storage.put_file(small_key, small_path, cache: :preview),
         {:ok, large_url} <- Storage.put_file(large_key, large_path, cache: :preview) do
      File.rm(small_path)
      File.rm(large_path)

      Media.complete_image(image, %{
        width: width,
        height: height,
        preview_small_key: small_key,
        preview_large_key: large_key,
        preview_small_url: small_url,
        preview_large_url: large_url,
        original_taken_at: timestamps.original_taken_at,
        effective_taken_at: timestamps.effective_taken_at,
        timezone_offset_minutes: timestamps.timezone_offset_minutes,
        time_source: timestamps.time_source,
        gps_latitude: gps_value(exif, :latitude),
        gps_longitude: gps_value(exif, :longitude)
      })
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  defp image_for(args, session) do
    case Map.get(args, "image_id") do
      nil -> Repo.get_by!(Image, upload_session_id: session.id)
      id -> Repo.get!(Image, id)
    end
  end

  defp original_path(%Image{} = image) do
    case Storage.fetch_to_temp(image.original_key) do
      {:ok, path} -> {:ok, path}
      {:error, reason} -> {:error, reason}
      :error -> {:error, :storage_adapter_cannot_provide_local_path}
    end
  end

  defp read_exif(path) do
    with {:ok, image} <- Elixir.Image.open(path),
         {:ok, exif} <- Elixir.Image.exif(image) do
      exif
    else
      _ -> %{}
    end
  end

  defp preview(path, size, quality) do
    target = Path.join(System.tmp_dir!(), "imaedge-#{System.unique_integer([:positive])}.webp")

    with {:ok, image} <- open_autorotated(path),
         {:ok, image} <- Elixir.Image.thumbnail(image, size),
         {:ok, _image} <- Elixir.Image.write(image, target, quality: quality) do
      {:ok, target}
    end
  end

  defp open_autorotated(path) do
    with {:ok, image} <- Elixir.Image.open(path),
         {:ok, {image, _flags}} <- Elixir.Image.autorotate(image) do
      {:ok, image}
    end
  end

  defp preview_key(%Image{} = image, filename) do
    image.original_key
    |> Path.dirname()
    |> Path.join(filename)
  end

  defp timestamps(exif, %UploadSession{} = session) do
    offset = session.timezone_offset_minutes

    case parse_exif_datetime(exif, offset) do
      {:ok, datetime, timezone_offset_minutes} ->
        %{
          original_taken_at: datetime,
          effective_taken_at: datetime,
          timezone_offset_minutes: timezone_offset_minutes,
          time_source: "exif"
        }

      :error ->
        fallback = session.finalized_at || session.inserted_at || DateTime.utc_now(:microsecond)

        %{
          original_taken_at: nil,
          effective_taken_at: fallback,
          timezone_offset_minutes: offset,
          time_source: "upload_time"
        }
    end
  end

  defp parse_exif_datetime(exif, fallback_offset_minutes) do
    with {:ok, naive} <- exif_datetime_original(exif),
         offset_minutes <- exif_timezone_offset(exif) || fallback_offset_minutes || 0 do
      offset_seconds = offset_minutes * 60
      datetime = DateTime.from_naive!(naive, "Etc/UTC") |> DateTime.add(-offset_seconds, :second)
      {:ok, datetime, offset_minutes}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp exif_datetime_original(exif) do
    exif_data = exif_section(exif)

    value =
      exif_data[:datetime_original] ||
        exif_data["DateTimeOriginal"] ||
        exif_data[:datetime] ||
        exif[:datetime_original] ||
        exif["DateTimeOriginal"] ||
        exif[:modify_date]

    naive_datetime(value)
  end

  defp naive_datetime(%NaiveDateTime{} = datetime), do: {:ok, datetime}

  defp naive_datetime(value) when is_binary(value) do
    value = String.replace(value, "T", " ")

    with [date, time] <- String.split(value, " ", parts: 2),
         [year, month, day] <- split_exif_date(date),
         [hour, minute, second] <- String.split(time, ":"),
         {second, microsecond} <- second_and_microsecond(second) do
      NaiveDateTime.new(
        String.to_integer(year),
        String.to_integer(month),
        String.to_integer(day),
        String.to_integer(hour),
        String.to_integer(minute),
        second,
        microsecond
      )
    else
      _ -> :error
    end
  end

  defp naive_datetime(_value), do: :error

  defp split_exif_date(date) do
    if String.contains?(date, ":") do
      String.split(date, ":")
    else
      String.split(date, "-")
    end
  end

  defp second_and_microsecond(value) do
    case String.split(value, ".", parts: 2) do
      [second] ->
        {String.to_integer(second), {0, 0}}

      [second, fraction] ->
        fraction = fraction |> String.slice(0, 6) |> String.pad_trailing(6, "0")
        {String.to_integer(second), {String.to_integer(fraction), 6}}
    end
  end

  defp exif_timezone_offset(exif) do
    exif_data = exif_section(exif)

    value =
      exif_data[:datetime_original_offset] ||
        exif_data[:time_offset] ||
        exif_data["OffsetTimeOriginal"] ||
        exif_data["TimeOffset"] ||
        exif[:time_offset] ||
        exif["OffsetTimeOriginal"]

    parse_offset_minutes(value)
  end

  defp parse_offset_minutes(value) when is_binary(value) do
    with [hours, minutes] <- String.split(value, ":", parts: 2),
         {hours, ""} <- Integer.parse(hours),
         {minutes, ""} <- Integer.parse(minutes) do
      sign = if String.starts_with?(value, "-"), do: -1, else: 1
      sign * (abs(hours) * 60 + minutes)
    else
      _ -> nil
    end
  end

  defp parse_offset_minutes(_value), do: nil

  defp exif_section(exif) do
    case exif[:exif] || exif["Exif"] || exif["exif"] do
      section when is_map(section) -> section
      _other -> %{}
    end
  end

  defp gps_value(exif, key) do
    gps = exif[:gps] || exif["gps"] || exif["GPS"] || %{}
    value = gps_coordinate(gps, key)
    ref = gps_ref(gps, key)

    decimal_gps(value, ref)
  end

  defp gps_coordinate(gps, :latitude) do
    gps_get(gps, :latitude) || gps_get(gps, :gps_latitude) || gps_get(gps, "GPSLatitude")
  end

  defp gps_coordinate(gps, :longitude) do
    gps_get(gps, :longitude) || gps_get(gps, :gps_longitude) || gps_get(gps, "GPSLongitude")
  end

  defp gps_ref(gps, :latitude) do
    gps_get(gps, :latitude_ref) || gps_get(gps, :gps_latitude_ref) ||
      gps_get(gps, "GPSLatitudeRef")
  end

  defp gps_ref(gps, :longitude) do
    gps_get(gps, :longitude_ref) || gps_get(gps, :gps_longitude_ref) ||
      gps_get(gps, "GPSLongitudeRef")
  end

  defp gps_get(gps, key) when is_map(gps), do: Map.get(gps, key)
  defp gps_get(_gps, _key), do: nil

  defp decimal_gps(nil, _ref), do: nil

  defp decimal_gps([degrees, minutes, seconds], ref) do
    value = to_float(degrees) + to_float(minutes) / 60 + to_float(seconds) / 3600
    value |> signed_gps(ref) |> Decimal.from_float()
  end

  defp decimal_gps(value, ref) when is_integer(value) or is_float(value) do
    value |> to_float() |> signed_gps(ref) |> Decimal.from_float()
  end

  defp decimal_gps(_value, _ref), do: nil

  defp signed_gps(value, ref) when ref in ["S", "W"], do: -value
  defp signed_gps(value, _ref), do: value

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1

  defp to_float(value) do
    value
    |> to_string()
    |> Float.parse()
    |> case do
      {number, _rest} -> number
      :error -> 0.0
    end
  end
end
