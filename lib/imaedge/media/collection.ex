defmodule Imaedge.Media.Collection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "collections" do
    field :public_id, :string

    has_many :images, Imaedge.Media.Image
    has_many :upload_sessions, Imaedge.Media.UploadSession

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:public_id])
    |> validate_required([:public_id])
    |> unique_constraint(:public_id)
  end
end
