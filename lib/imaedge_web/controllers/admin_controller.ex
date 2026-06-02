defmodule ImaedgeWeb.AdminController do
  use ImaedgeWeb, :controller

  alias Imaedge.Admin

  def show(conn, params) do
    usage = Admin.usage(params)

    render(conn, :show,
      page_title: "Admin",
      meta_title: "Admin | imaedge",
      meta_description: "Private imaedge usage and health statistics.",
      meta_url: url(~p"/admin"),
      usage: usage
    )
  end
end
