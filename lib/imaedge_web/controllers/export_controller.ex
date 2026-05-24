defmodule ImaedgeWeb.ExportController do
  use ImaedgeWeb, :controller

  alias Imaedge.Media

  def show(conn, %{"id" => public_id}) do
    collection = Media.get_collection_by_public_id!(public_id)
    images = Media.list_gallery_images(collection)

    render(conn, :show, collection: collection, images: images)
  end
end
