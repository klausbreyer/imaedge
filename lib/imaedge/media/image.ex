defmodule Imaedge.Media.Image do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(processing complete pending_delete deleted)

  schema "images" do
    field :public_id, :string
    field :image_secret, :string
    field :contributor_id, :string
    field :original_filename, :string
    field :mime, :string
    field :byte_size, :integer
    field :sha256, :string
    field :width, :integer
    field :height, :integer
    field :original_key, :string
    field :preview_small_key, :string
    field :preview_large_key, :string
    field :original_url, :string
    field :preview_small_url, :string
    field :preview_large_url, :string
    field :original_taken_at, :utc_datetime_usec
    field :effective_taken_at, :utc_datetime_usec
    field :timezone_offset_minutes, :integer
    field :time_source, :string
    field :gps_latitude, :decimal
    field :gps_longitude, :decimal
    field :status, :string, default: "processing"
    field :delete_after, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    belongs_to :collection, Imaedge.Media.Collection
    belongs_to :upload_session, Imaedge.Media.UploadSession

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(image, attrs) do
    image
    |> cast(attrs, [
      :public_id,
      :image_secret,
      :collection_id,
      :upload_session_id,
      :contributor_id,
      :original_filename,
      :mime,
      :byte_size,
      :sha256,
      :width,
      :height,
      :original_key,
      :preview_small_key,
      :preview_large_key,
      :original_url,
      :preview_small_url,
      :preview_large_url,
      :original_taken_at,
      :effective_taken_at,
      :timezone_offset_minutes,
      :time_source,
      :gps_latitude,
      :gps_longitude,
      :status,
      :delete_after,
      :deleted_at
    ])
    |> validate_required([
      :public_id,
      :image_secret,
      :collection_id,
      :contributor_id,
      :original_filename,
      :mime,
      :byte_size,
      :sha256,
      :original_key,
      :original_url,
      :effective_taken_at,
      :time_source,
      :status
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:sha256, ~r/\A[0-9a-f]{64}\z/)
    |> unique_constraint(:public_id)
    |> unique_constraint(:sha256, name: :images_collection_id_sha256_index)
  end
end
