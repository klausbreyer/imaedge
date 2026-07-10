defmodule ImaedgeWeb.PageControllerTest do
  use ImaedgeWeb.ConnCase
  alias Imaedge.Media
  import Phoenix.LiveViewTest

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Images."
    assert response =~ "start a collection"
    assert response =~ "data-collection-name-form"
    assert response =~ "noindex"
    assert response =~ "Apple shared albums compress"
    assert response =~ "Google Photos wants everything synced"
    assert response =~ "printed photo album"
    assert response =~ "imaedge is open source"
    assert response =~ "Open source on GitHub"
    assert response =~ ~s(<meta property="og:title" content="imaedge")
    assert response =~ ~s(<meta property="og:type" content="website")
    assert response =~ ~s(<meta property="og:url" content="#{ImaedgeWeb.Endpoint.url()}/")

    assert response =~
             ~s(<meta property="og:image" content="#{ImaedgeWeb.Endpoint.url()}/images/og/home.png")

    assert response =~ ~s(<meta name="twitter:card" content="summary")
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

  test "collection page includes share metadata", %{conn: conn} do
    {:ok, collection} = Media.create_collection(%{name: "Beach Phone Dump"})

    conn = get(conn, ~p"/i/#{collection.public_id}")
    response = html_response(conn, 200)

    assert response =~ ~s(<meta property="og:title" content="Beach Phone Dump | imaedge")

    assert response =~
             ~s(<meta property="og:url" content="#{ImaedgeWeb.Endpoint.url()}/i/#{collection.public_id}")

    assert response =~
             ~s(<meta name="description" content="Upload and collect original-quality photos in this shared imaedge collection.")
  end

  test "export page uses compact header actions", %{conn: conn} do
    {:ok, collection} = Media.create_collection(%{name: "Beach Phone Dump"})

    conn = get(conn, ~p"/i/#{collection.public_id}/export")
    response = html_response(conn, 200)

    assert response =~ "opened"
    assert response =~ "edited"
    assert response =~ ~s(href="/i/#{collection.public_id}")
    assert response =~ "workspace"
    assert response =~ "print"
    refute response =~ "back to workspace"
    refute response =~ "print / save PDF"
    refute response =~ "imaedge.app/i/#{collection.public_id}"
  end

  test "export page includes export metadata", %{conn: conn} do
    {:ok, collection} = Media.create_collection(%{name: "Beach Phone Dump"})

    conn = get(conn, ~p"/i/#{collection.public_id}/export")
    response = html_response(conn, 200)

    assert response =~ ~s(<meta property="og:title" content="Export Beach Phone Dump | imaedge")

    assert response =~
             ~s(<meta property="og:url" content="#{ImaedgeWeb.Endpoint.url()}/i/#{collection.public_id}/export")
  end
end
