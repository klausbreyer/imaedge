defmodule Imaedge.MediaTest do
  use Imaedge.DataCase

  alias Imaedge.Media
  alias Imaedge.Media.Image

  test "move_image rebalances when adjacent timestamps leave no midpoint" do
    {:ok, collection} = Media.create_collection()
    base = ~U[2026-05-24 12:00:00.000000Z]

    first = insert_image!(collection, "first", base, 1)
    second = insert_image!(collection, "second", DateTime.add(base, 1, :microsecond), 2)
    third = insert_image!(collection, "third", DateTime.add(base, 2, :microsecond), 3)

    assert Enum.map(Media.list_gallery_images(collection), & &1.public_id) == [
             first.public_id,
             second.public_id,
             third.public_id
           ]

    assert {:ok, _image} = Media.move_image(collection, third.public_id, "earlier")

    moved_order = Media.list_gallery_images(collection)

    assert Enum.map(moved_order, & &1.public_id) == [
             first.public_id,
             third.public_id,
             second.public_id
           ]

    [left, middle, right] = moved_order
    assert DateTime.diff(middle.effective_taken_at, left.effective_taken_at, :microsecond) > 1
    assert DateTime.diff(right.effective_taken_at, middle.effective_taken_at, :microsecond) > 1
  end

  test "move_image can keep moving after a rebalance" do
    {:ok, collection} = Media.create_collection()
    base = ~U[2026-05-24 12:00:00.000000Z]

    first = insert_image!(collection, "first", base, 1)
    second = insert_image!(collection, "second", DateTime.add(base, 1, :microsecond), 2)
    third = insert_image!(collection, "third", DateTime.add(base, 2, :microsecond), 3)

    assert {:ok, _image} = Media.move_image(collection, third.public_id, "earlier")
    assert {:ok, _image} = Media.move_image(collection, third.public_id, "earlier")

    assert Enum.map(Media.list_gallery_images(collection), & &1.public_id) == [
             third.public_id,
             first.public_id,
             second.public_id
           ]
  end

  test "update_effective_time accepts datetime-local input" do
    {:ok, collection} = Media.create_collection()
    image = insert_image!(collection, "first", ~U[2026-05-24 12:00:00.000000Z], 1)

    assert {:ok, image} =
             Media.update_effective_time(
               collection,
               image.public_id,
               "2026-05-24T17:23:05.219183"
             )

    assert image.effective_taken_at == ~U[2026-05-24 17:23:05.219183Z]
  end

  test "update_effective_time keeps the image timezone for datetime-local input" do
    {:ok, collection} = Media.create_collection()
    image = insert_image!(collection, "first", ~U[2026-05-24 12:00:00.000000Z], 1)
    {:ok, image} = Image.changeset(image, %{timezone_offset_minutes: -600}) |> Repo.update()

    assert {:ok, image} =
             Media.update_effective_time(collection, image.public_id, "2025-07-28T10:32:48")

    assert DateTime.compare(image.effective_taken_at, ~U[2025-07-28 20:32:48Z]) == :eq
  end

  test "update_effective_time accepts minute precision datetime-local input" do
    {:ok, collection} = Media.create_collection()
    image = insert_image!(collection, "first", ~U[2026-05-24 12:00:00.000000Z], 1)
    {:ok, image} = Image.changeset(image, %{timezone_offset_minutes: -600}) |> Repo.update()

    assert {:ok, image} =
             Media.update_effective_time(collection, image.public_id, "2025-07-28T10:32")

    assert DateTime.compare(image.effective_taken_at, ~U[2025-07-28 20:32:00Z]) == :eq
  end

  defp insert_image!(collection, public_id, effective_taken_at, index) do
    %Image{}
    |> Image.changeset(%{
      public_id: public_id,
      image_secret: "#{public_id}-secret",
      collection_id: collection.id,
      contributor_id: "clear-signal",
      original_filename: "#{public_id}.png",
      mime: "image/png",
      byte_size: 10,
      sha256: sha256(index),
      width: 10,
      height: 10,
      original_key: "collections/#{collection.public_id}/#{public_id}/original.png",
      original_url: "https://example.test/#{public_id}/original.png",
      preview_small_url: "https://example.test/#{public_id}/small.webp",
      preview_large_url: "https://example.test/#{public_id}/large.webp",
      effective_taken_at: effective_taken_at,
      time_source: "upload_time",
      status: "complete"
    })
    |> Repo.insert!()
  end

  defp sha256(index) do
    index
    |> Integer.to_string(16)
    |> String.pad_leading(64, "0")
  end
end
