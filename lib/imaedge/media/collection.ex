defmodule Imaedge.Media.Collection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "collections" do
    field :public_id, :string
    field :name, :string

    has_many :images, Imaedge.Media.Image
    has_many :upload_sessions, Imaedge.Media.UploadSession

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:public_id, :name])
    |> update_change(:name, &blank_to_nil/1)
    |> validate_required([:public_id])
    |> validate_format(:public_id, ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
    |> validate_length(:name, max: 80)
    |> unique_constraint(:public_id)
  end

  def display_name(%__MODULE__{name: name, public_id: public_id}) do
    case blank_to_nil(name) do
      nil -> public_id
      value -> value
    end
  end

  def named?(%__MODULE__{name: name}), do: blank_to_nil(name) != nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 80)
    end
  end

  defp blank_to_nil(value), do: value
end
