defmodule ImaedgeWeb.PageController do
  use ImaedgeWeb, :controller
  alias Imaedge.Media

  def home(conn, _params) do
    render(conn, :home)
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def create(conn, params) do
    {:ok, collection} = Media.create_collection(params)
    redirect(conn, to: ~p"/i/#{collection.public_id}")
  end
end
