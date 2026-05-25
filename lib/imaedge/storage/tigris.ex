defmodule Imaedge.Storage.Tigris do
  @moduledoc false

  # Originals can be tens of megabytes and Tigris is upstream, so give the
  # PUT a generous receive_timeout. The default Req timeout is too short for
  # mobile uploads of full-resolution photos.
  @put_receive_timeout :timer.minutes(5)
  @put_pool_timeout :timer.seconds(30)
  @delete_receive_timeout :timer.seconds(30)

  def put_file(key, source_path, opts \\ []) do
    body = File.read!(source_path)
    headers = request_headers(key, body, opts)

    case Req.put(object_url(key),
           body: body,
           headers: headers,
           receive_timeout: @put_receive_timeout,
           pool_timeout: @put_pool_timeout,
           retry: false
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, public_url(key)}

      {:ok, response} ->
        {:error, {:tigris_put_failed, response.status, response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete(key) do
    headers = signed_headers("DELETE", object_url(key), [], "")

    case Req.delete(object_url(key),
           headers: headers,
           receive_timeout: @delete_receive_timeout,
           retry: false
         ) do
      {:ok, %{status: status}} when status in [200, 202, 204, 404] -> :ok
      {:ok, response} -> {:error, {:tigris_delete_failed, response.status, response.body}}
      {:error, reason} -> {:error, reason}
    end
  end

  def public_url(key) do
    public_base_url()
    |> String.trim_trailing("/")
    |> Kernel.<>("/#{key}")
  end

  def fetch_to_temp(key) do
    url = object_url(key)
    headers = signed_headers("GET", url, [], "")

    case Req.get(url, headers: headers) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        path =
          Path.join(System.tmp_dir!(), "imaedge-object-#{System.unique_integer([:positive])}")

        File.write!(path, body)
        {:ok, path}

      {:ok, response} ->
        {:error, {:tigris_get_failed, response.status, response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_headers(key, body, opts) do
    headers =
      []
      |> maybe_put_header("content-type", content_type(key))
      |> maybe_put_header("cache-control", cache_control(opts[:cache]))

    signed_headers("PUT", object_url(key), headers, body)
  end

  defp signed_headers(method, url, headers, body) do
    host = url |> URI.parse() |> Map.fetch!(:host)
    headers = [{"host", host} | headers]

    signed_headers =
      :aws_signature.sign_v4(
        access_key_id(),
        secret_access_key(),
        region(),
        "s3",
        :calendar.universal_time(),
        method,
        url,
        Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end),
        body,
        uri_encode_path: false
      )

    signed_headers
    |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
    |> Enum.reject(fn {key, _value} -> String.downcase(key) == "host" end)
  end

  defp object_url(key) do
    endpoint()
    |> String.trim_trailing("/")
    |> Kernel.<>("/#{bucket_name()}/#{key}")
  end

  defp cache_control(:preview), do: "public, max-age=31536000, immutable"
  defp cache_control(:original), do: "public, max-age=3600"
  defp cache_control(_other), do: nil

  defp content_type(key) do
    case Path.extname(key) do
      ".webp" -> "image/webp"
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      _ -> "application/octet-stream"
    end
  end

  defp maybe_put_header(headers, _key, nil), do: headers
  defp maybe_put_header(headers, key, value), do: [{key, value} | headers]

  defp endpoint do
    System.get_env("AWS_ENDPOINT_URL_S3") || "https://t3.storage.dev"
  end

  defp public_base_url do
    System.get_env("TIGRIS_PUBLIC_BASE_URL") || "https://#{bucket_name()}.t3.tigrisfiles.io"
  end

  defp bucket_name do
    System.get_env("BUCKET_NAME") || raise "environment variable BUCKET_NAME is missing"
  end

  defp access_key_id do
    System.get_env("AWS_ACCESS_KEY_ID") ||
      raise "environment variable AWS_ACCESS_KEY_ID is missing"
  end

  defp secret_access_key do
    System.get_env("AWS_SECRET_ACCESS_KEY") ||
      raise "environment variable AWS_SECRET_ACCESS_KEY is missing"
  end

  defp region do
    System.get_env("AWS_REGION") || "auto"
  end
end
