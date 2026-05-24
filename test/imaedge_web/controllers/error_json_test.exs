defmodule ImaedgeWeb.ErrorJSONTest do
  use ImaedgeWeb.ConnCase, async: true

  test "renders 404" do
    assert ImaedgeWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert ImaedgeWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
