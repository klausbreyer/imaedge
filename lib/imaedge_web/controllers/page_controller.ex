defmodule ImaedgeWeb.PageController do
  use ImaedgeWeb, :controller
  alias Imaedge.Media

  @home_description "Collect original-quality photos together through one private link. No account, no compression, built for shaky travel uploads."
  @about_description "imaedge is a small open source tool for collecting original-quality photos from multiple people through one private link."
  @privacy_description "How imaedge handles private collection links, original image uploads, storage, and export data."

  def home(conn, _params) do
    render(conn, :home,
      page_title: "imaedge",
      meta_description: @home_description,
      meta_url: url(~p"/")
    )
  end

  def about(conn, _params) do
    render(conn, :about,
      page_title: "About imaedge",
      meta_description: @about_description,
      meta_url: url(~p"/about")
    )
  end

  def privacy(conn, _params) do
    render(conn, :privacy,
      page_title: "Privacy",
      meta_title: "Privacy | imaedge",
      meta_description: @privacy_description,
      meta_url: url(~p"/privacy")
    )
  end

  def create(conn, params) do
    {:ok, collection} = Media.create_collection(params)
    redirect(conn, to: ~p"/i/#{collection.public_id}")
  end
end
