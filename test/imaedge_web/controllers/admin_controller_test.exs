defmodule ImaedgeWeb.AdminControllerTest do
  use ImaedgeWeb.ConnCase

  alias Imaedge.Media
  alias Imaedge.Media.Image
  alias Imaedge.Repo

  test "GET /admin requires basic auth", %{conn: conn} do
    conn = get(conn, ~p"/admin")

    assert response(conn, 401)
    assert get_resp_header(conn, "www-authenticate") != []
  end

  test "GET /admin renders usage without private upload details", %{conn: conn} do
    {:ok, collection} = Media.create_collection(%{name: "Beach Phone Dump"})

    {:ok, upload} =
      Media.create_upload_session(collection, %{
        "contributor_id" => "visitor-a",
        "filename" => "private-original-name.jpg",
        "mime" => "image/jpeg",
        "byte_size" => 2_048,
        "sha256" => String.duplicate("a", 64)
      })

    {:ok, upload} =
      Media.update_upload_session(upload, %{
        status: "done",
        finalized_at: DateTime.utc_now(:microsecond)
      })

    {:ok, _image} =
      %Image{}
      |> Image.changeset(%{
        public_id: "imgpublic123",
        image_secret: "secret123",
        collection_id: collection.id,
        upload_session_id: upload.id,
        contributor_id: "visitor-a",
        original_filename: "private-original-name.jpg",
        mime: "image/jpeg",
        byte_size: 2_048,
        sha256: String.duplicate("a", 64),
        original_key: "collections/#{collection.public_id}/secret123/original.jpg",
        original_url: "/objects/collections/#{collection.public_id}/secret123/original.jpg",
        effective_taken_at: DateTime.utc_now(:microsecond),
        time_source: "upload_time",
        status: "complete"
      })
      |> Repo.insert()

    {:ok, failed_upload} =
      Media.create_upload_session(collection, %{
        "contributor_id" => "visitor-b",
        "filename" => "failed-private-name.png",
        "mime" => "image/png",
        "byte_size" => 4_096,
        "sha256" => String.duplicate("b", 64)
      })

    {:ok, _failed_upload} =
      Media.update_upload_session(failed_upload, %{
        status: "failed",
        error_message: "could not decode image"
      })

    conn = conn |> with_admin_auth() |> get(~p"/admin?days=365")
    response = html_response(conn, 200)

    assert response =~ "Usage and health"
    assert response =~ "Beach Phone Dump"
    assert response =~ ~s(href="/i/#{collection.public_id}")
    assert response =~ "2.0 KiB"
    assert response =~ "could not decode image"
    refute response =~ "private-original-name.jpg"
    refute response =~ "failed-private-name.png"
    refute response =~ String.duplicate("a", 64)
    refute response =~ String.duplicate("b", 64)
  end

  defp with_admin_auth(conn) do
    put_req_header(conn, "authorization", "Basic " <> Base.encode64("admin:admin"))
  end
end
