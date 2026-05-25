defmodule ImaedgeWeb.PageControllerTest do
  use ImaedgeWeb.ConnCase
  alias Imaedge.Media

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Images."
    assert response =~ "Start a collection"
    assert response =~ "data-collection-name-form"
    assert response =~ "noindex"
  end

  test "POST /collections creates a named collection with a place URL", %{conn: conn} do
    conn = post(conn, ~p"/collections", %{name: "Norway Roadtrip"})

    assert "/i/" <> public_id = redirected_to(conn)
    assert public_id =~ ~r/\A[a-z]+-[a-z]+-[a-z]+-[a-z0-9]{10}\z/

    collection = Media.get_collection_by_public_id!(public_id)
    assert collection.name == "Norway Roadtrip"
  end
end
