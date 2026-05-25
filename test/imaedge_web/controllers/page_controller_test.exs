defmodule ImaedgeWeb.PageControllerTest do
  use ImaedgeWeb.ConnCase
  alias Imaedge.Media
  import Phoenix.LiveViewTest

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

  test "collection page includes a browser share CTA", %{conn: conn} do
    {:ok, collection} = Media.create_collection(%{name: "Beach Phone Dump"})

    {:ok, _view, html} = live(conn, ~p"/i/#{collection.public_id}")

    assert html =~ ~s(id="share-collection-link")
    assert html =~ ~s(phx-hook="ShareCollectionLink")
    assert html =~ ~s(data-collection-url=)
    assert html =~ ~s(/i/#{collection.public_id})
    assert html =~ ~s(href="/i/#{collection.public_id}/export")
    refute html =~ ~s(href="/i/#{collection.public_id}")
    refute html =~ "copy collection link"
    refute html =~ "export HTML"
    assert html =~ "export"
    assert html =~ "share"
  end
end
