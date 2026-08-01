defmodule ImaedgeWeb.UploadControllerTest do
  use ImaedgeWeb.ConnCase

  alias Imaedge.Media
  alias Imaedge.Uploads

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

  test "cancel stops an active upload session", %{conn: conn} do
    {:ok, collection} = Media.create_collection()
    {:ok, session} = upload_session(collection, "cancel-me.png")

    conn = delete(conn, ~p"/i/#{collection.public_id}/uploads/#{session.public_id}")

    assert json_response(conn, 200) == %{"status" => "cancelled"}
    assert Media.get_upload_session!(collection, session.public_id).status == "cancelled"
    assert Media.list_visible_uploads(collection) == []
  end

  test "a stale chunk request cannot revive a cancelled upload", %{conn: conn} do
    {:ok, collection} = Media.create_collection()
    {:ok, session} = upload_session(collection, "cancel-race.png")

    conn = delete(conn, ~p"/i/#{collection.public_id}/uploads/#{session.public_id}")
    assert json_response(conn, 200) == %{"status" => "cancelled"}

    assert {:error, :cancelled} = Uploads.write_chunk(session, 0, "stale chunk")
    assert Media.get_upload_session!(collection, session.public_id).status == "cancelled"
  end

  test "cancel does not remove an accepted upload", %{conn: conn} do
    {:ok, collection} = Media.create_collection()
    {:ok, session} = upload_session(collection, "accepted.png")
    {:ok, _session} = Media.update_upload_session(session, %{status: "processing"})

    conn = delete(conn, ~p"/i/#{collection.public_id}/uploads/#{session.public_id}")

    assert json_response(conn, 409) == %{"error" => "already_accepted"}
    assert Media.get_upload_session!(collection, session.public_id).status == "processing"
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
