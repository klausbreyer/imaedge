defmodule ImaedgeWeb.PageController do
  use ImaedgeWeb, :controller
  alias Imaedge.Media

  def home(conn, _params) do
    render(conn, :home)
  end

  def create(conn, _params) do
    {:ok, collection} = Media.create_collection()
    redirect(conn, to: ~p"/i/#{collection.public_id}")
  end
end
