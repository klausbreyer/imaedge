defmodule ImaedgeWeb.PageControllerTest do
  use ImaedgeWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Collect original photos"
    assert response =~ "New collection"
    assert response =~ "noindex"
  end

  test "POST /collections creates and redirects to a secret collection", %{conn: conn} do
    conn = post(conn, ~p"/collections")

    assert "/i/" <> public_id = redirected_to(conn)
    assert String.length(public_id) >= 24
  end
end
