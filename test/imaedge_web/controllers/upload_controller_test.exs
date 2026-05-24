defmodule ImaedgeWeb.UploadControllerTest do
  use ImaedgeWeb.ConnCase

  alias Imaedge.Media

  @sha256 String.duplicate("a", 64)

  test "show reports a duplicate for a stale upload session", %{conn: conn} do
    {collection, stale_session, duplicate} = collection_with_duplicate()

    conn = get(conn, ~p"/i/#{collection.public_id}/uploads/#{stale_session.public_id}")
    body = json_response(conn, 200)

    assert body["duplicate"] == true
    assert body["image_id"] == duplicate.public_id
    assert body["missing_chunks"] == [0]
  end

  test "finalize releases a stale upload session when the image already exists", %{conn: conn} do
    {collection, stale_session, duplicate} = collection_with_duplicate()

    conn = post(conn, ~p"/i/#{collection.public_id}/uploads/#{stale_session.public_id}/finalize")
    body = json_response(conn, 200)

    assert body == %{
             "duplicate" => true,
             "image_id" => duplicate.public_id,
             "status" => "done"
           }
  end

  defp collection_with_duplicate do
    {:ok, collection} = Media.create_collection()
    {:ok, completed_session} = upload_session(collection, "already-uploaded.png")

    {:ok, image} =
      Media.create_processing_image(
        completed_session,
        "imageSecret1",
        "objects/original.png",
        "https://example.test/original.png"
      )

    {:ok, duplicate} = Media.complete_image(image, %{width: 100, height: 80})

    {:ok, stale_session} = upload_session(collection, "stale-local-copy.png")

    {collection, stale_session, duplicate}
  end

  defp upload_session(collection, filename) do
    Media.create_upload_session(collection, %{
      "filename" => filename,
      "mime" => "image/png",
      "byte_size" => 10,
      "sha256" => @sha256,
      "contributor_id" => "quiet-river",
      "timezone_offset_minutes" => 0
    })
  end
end
