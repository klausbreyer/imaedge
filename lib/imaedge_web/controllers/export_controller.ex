defmodule ImaedgeWeb.ExportController do
  use ImaedgeWeb, :controller

  alias Imaedge.Media
  alias Imaedge.Media.Collection

  def show(conn, %{"id" => public_id}) do
    collection = Media.get_collection_by_public_id!(public_id)
    images = Media.list_gallery_images(collection)
    last_activity_at = Media.last_activity_at(collection)
    collection_name = Collection.display_name(collection)

    render(conn, :show,
      page_title: collection_name,
      meta_title: "Export #{collection_name} | imaedge",
      meta_description: "Export original-quality photos from this shared imaedge collection.",
      meta_url: url(~p"/i/#{collection.public_id}/export"),
      collection: collection,
      images: images,
      opened_at: collection.inserted_at,
      last_activity_at: last_activity_at
    )
  end
end
