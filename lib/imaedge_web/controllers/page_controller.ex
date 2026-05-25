defmodule ImaedgeWeb.PageController do
  use ImaedgeWeb, :controller
  alias Imaedge.Media

  def home(conn, _params) do
    render(conn, :home)
  end

  def create(conn, params) do
    {:ok, collection} = Media.create_collection(params)
    redirect(conn, to: ~p"/i/#{collection.public_id}")
  end
end
