defmodule ImaedgeWeb.ExportController do
  use ImaedgeWeb, :controller

  alias Imaedge.Media

  def show(conn, %{"id" => public_id}) do
    collection = Media.get_collection_by_public_id!(public_id)
    images = Media.list_gallery_images(collection)
    last_activity_at = Media.last_activity_at(collection)

    render(conn, :show,
      collection: collection,
      images: images,
      opened_at: collection.inserted_at,
      last_activity_at: last_activity_at
    )
  end
end
