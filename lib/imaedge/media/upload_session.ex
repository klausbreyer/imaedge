defmodule Imaedge.Media.UploadSession do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(created uploading finalizing processing failed done duplicate)

  schema "upload_sessions" do
    field :public_id, :string
    field :contributor_id, :string
    field :original_filename, :string
    field :mime, :string
    field :byte_size, :integer
    field :sha256, :string
    field :timezone_offset_minutes, :integer
    field :chunk_size, :integer
    field :total_chunks, :integer
    field :status, :string, default: "created"
    field :object_key, :string
    field :original_url, :string
    field :error_message, :string
    field :finalized_at, :utc_datetime_usec

    belongs_to :collection, Imaedge.Media.Collection
    has_one :image, Imaedge.Media.Image

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(upload_session, attrs) do
    upload_session
    |> cast(attrs, [
      :public_id,
      :collection_id,
      :contributor_id,
      :original_filename,
      :mime,
      :byte_size,
      :sha256,
      :timezone_offset_minutes,
      :chunk_size,
      :total_chunks,
      :status,
      :object_key,
      :original_url,
      :error_message,
      :finalized_at
    ])
    |> validate_required([
      :public_id,
      :collection_id,
      :contributor_id,
      :original_filename,
      :mime,
      :byte_size,
      :sha256,
      :chunk_size,
      :total_chunks,
      :status
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:byte_size, greater_than: 0)
    |> validate_number(:chunk_size, greater_than: 0)
    |> validate_number(:total_chunks, greater_than: 0)
    |> validate_format(:sha256, ~r/\A[0-9a-f]{64}\z/)
    |> unique_constraint(:public_id)
  end
end
