defmodule Imaedge.Repo.Migrations.CreateCollectionsUploadsImages do
  use Ecto.Migration

  def change do
    create table(:collections) do
      add :public_id, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:collections, [:public_id])

    create table(:upload_sessions) do
      add :public_id, :string, null: false
      add :collection_id, references(:collections, on_delete: :delete_all), null: false
      add :contributor_id, :string, null: false
      add :original_filename, :string, null: false
      add :mime, :string, null: false
      add :byte_size, :bigint, null: false
      add :sha256, :string, null: false
      add :timezone_offset_minutes, :integer
      add :chunk_size, :integer, null: false
      add :total_chunks, :integer, null: false
      add :status, :string, null: false, default: "created"
      add :object_key, :string
      add :original_url, :string
      add :error_message, :text
      add :finalized_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:upload_sessions, [:public_id])
    create index(:upload_sessions, [:collection_id, :status])
    create index(:upload_sessions, [:collection_id, :sha256])

    create table(:images) do
      add :public_id, :string, null: false
      add :image_secret, :string, null: false
      add :collection_id, references(:collections, on_delete: :delete_all), null: false
      add :upload_session_id, references(:upload_sessions, on_delete: :nilify_all)
      add :contributor_id, :string, null: false
      add :original_filename, :string, null: false
      add :mime, :string, null: false
      add :byte_size, :bigint, null: false
      add :sha256, :string, null: false
      add :width, :integer
      add :height, :integer
      add :original_key, :string, null: false
      add :preview_small_key, :string
      add :preview_large_key, :string
      add :original_url, :string, null: false
      add :preview_small_url, :string
      add :preview_large_url, :string
      add :original_taken_at, :utc_datetime_usec
      add :effective_taken_at, :utc_datetime_usec, null: false
      add :timezone_offset_minutes, :integer
      add :time_source, :string, null: false
      add :gps_latitude, :decimal
      add :gps_longitude, :decimal
      add :status, :string, null: false, default: "processing"
      add :delete_after, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:images, [:public_id])
    create unique_index(:images, [:collection_id, :sha256], where: "deleted_at IS NULL")
    create index(:images, [:collection_id, :effective_taken_at])
    create index(:images, [:collection_id, :status])
  end
end
