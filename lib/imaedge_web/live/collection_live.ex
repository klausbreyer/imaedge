defmodule ImaedgeWeb.CollectionLive do
  use ImaedgeWeb, :live_view

  alias Imaedge.Media

  def mount(%{"id" => public_id}, _session, socket) do
    collection = Media.get_collection_by_public_id!(public_id)

    if connected?(socket) do
      Media.subscribe(collection)
    end

    {:ok,
     socket
     |> assign(:page_title, "imaedge")
     |> assign(:collection, collection)
     |> assign(:image_count, 0)
     |> assign(:upload_count, 0)
     |> reload()}
  end

  def handle_event("move", %{"id" => image_id, "direction" => direction}, socket) do
    Media.move_image(socket.assigns.collection, image_id, direction)
    {:noreply, reload(socket)}
  end

  def handle_event(
        "set_time",
        %{"image-id" => image_id, "time_edit" => %{"datetime" => value}},
        socket
      ) do
    case Media.update_effective_time(socket.assigns.collection, image_id, value) do
      {:ok, _image} -> {:noreply, reload(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Could not update time")}
    end
  end

  def handle_event("delete", %{"id" => image_id}, socket) do
    Media.mark_pending_delete(socket.assigns.collection, image_id)

    {:noreply,
     socket
     |> put_flash(:info, "Image hidden. Undo is available for 10 seconds.")
     |> push_event("imaedge:delete-started", %{image_id: image_id})
     |> reload()}
  end

  def handle_event("undo_delete", %{"id" => image_id}, socket) do
    Media.undo_delete(socket.assigns.collection, image_id)
    {:noreply, reload(socket)}
  end

  def handle_event("retry_upload", %{"id" => upload_id}, socket) do
    Media.retry_failed_upload(socket.assigns.collection, upload_id)
    {:noreply, reload(socket)}
  end

  def handle_event("remove_upload", %{"id" => upload_id}, socket) do
    Media.remove_failed_upload(socket.assigns.collection, upload_id)
    {:noreply, reload(socket)}
  end

  def handle_info(_message, socket) do
    {:noreply, reload(socket)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="workspace-head">
        <div>
          <p class="eyebrow">collection</p>
          <h1>{@collection.public_id}</h1>
        </div>
        <a class="quiet-link" href={~p"/i/#{@collection.public_id}/export"}>Export HTML</a>
      </section>

      <section
        id="upload-queue"
        class="upload-panel"
        phx-hook="UploadQueue"
        phx-update="ignore"
        data-collection-id={@collection.public_id}
      >
        <div class="panel-head">
          <div>
            <p class="eyebrow">local queue</p>
            <h2>Uploads</h2>
          </div>
          <label class="file-button">
            <.icon name="hero-arrow-up-tray" class="size-5" /> Select images
            <input id="image-picker" type="file" accept="image/jpeg,image/png,image/webp" multiple />
          </label>
        </div>

        <div class="queue-controls">
          <label>
            Parallel uploads
            <select id="upload-concurrency">
              <option value="1" selected>1</option>
              <option value="2">2</option>
              <option value="3">3</option>
            </select>
          </label>
          <span id="storage-estimate">Storage estimate pending</span>
        </div>

        <div id="client-queue" class="client-queue"></div>

        <details class="debug-log">
          <summary>Debug log</summary>
          <button id="copy-debug-log" type="button">Copy log</button>
          <button id="clear-debug-log" type="button">Clear</button>
          <pre id="debug-log-output"></pre>
        </details>
      </section>

      <section class="server-uploads">
        <div class="section-title">
          <h2>Server processing</h2>
          <span>{@upload_count}</span>
        </div>

        <div id="server-upload-list" phx-update="stream" class="server-upload-list">
          <div class="empty-state hidden only:block">No server-side uploads waiting.</div>
          <article :for={{dom_id, upload} <- @streams.uploads} id={dom_id} class="server-upload">
            <div>
              <strong>{upload.original_filename}</strong>
              <span>{upload.status}</span>
              <%= if upload.error_message do %>
                <code>{upload.error_message}</code>
              <% end %>
            </div>
            <div class="row-actions">
              <button
                :if={upload.status == "failed"}
                type="button"
                phx-click="retry_upload"
                phx-value-id={upload.public_id}
              >
                Retry
              </button>
              <button
                :if={upload.status == "failed"}
                type="button"
                phx-click="remove_upload"
                phx-value-id={upload.public_id}
              >
                Remove
              </button>
            </div>
          </article>
        </div>
      </section>

      <section class="gallery-section">
        <div class="section-title">
          <h2>Gallery</h2>
          <span>{@image_count}</span>
        </div>

        <div id="gallery-grid" phx-update="stream" class="gallery-grid">
          <div class="empty-state hidden only:block">No images yet.</div>
          <article :for={{dom_id, image} <- @streams.images} id={dom_id} class="image-tile">
            <a href={image.preview_large_url || image.original_url} class="image-preview">
              <img
                src={image.preview_small_url || image.original_url}
                loading="lazy"
                alt={image.original_filename}
              />
            </a>

            <div class="tile-meta">
              <span>{image.contributor_id}</span>
              <span>{format_time(image.effective_taken_at)}</span>
            </div>

            <div class="tile-actions">
              <button
                type="button"
                title="Move earlier"
                phx-click="move"
                phx-value-id={image.public_id}
                phx-value-direction="earlier"
              >
                <.icon name="hero-chevron-left" class="size-4" />
              </button>
              <button
                type="button"
                title="Move later"
                phx-click="move"
                phx-value-id={image.public_id}
                phx-value-direction="later"
              >
                <.icon name="hero-chevron-right" class="size-4" />
              </button>
              <a
                href={image.original_url}
                download={Map.fetch!(@download_names, image.public_id)}
                title="Download original"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" />
              </a>
              <button type="button" title="Delete" phx-click="delete" phx-value-id={image.public_id}>
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>

            <.form for={time_form(image)} id={"time-form-#{image.public_id}"} phx-submit="set_time">
              <input type="hidden" name="image-id" value={image.public_id} />
              <.input
                field={time_form(image)[:datetime]}
                type="datetime-local"
                label="Album time"
                step="0.000001"
              />
              <button type="submit">Save time</button>
            </.form>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp reload(socket) do
    images = Media.list_gallery_images(socket.assigns.collection)
    uploads = Media.list_visible_uploads(socket.assigns.collection)

    socket
    |> assign(:image_count, length(images))
    |> assign(:upload_count, length(uploads))
    |> assign(:download_names, download_names(images))
    |> stream(:images, images, reset: true)
    |> stream(:uploads, uploads, reset: true)
  end

  defp format_time(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp time_form(image) do
    value =
      image.effective_taken_at
      |> DateTime.to_naive()
      |> NaiveDateTime.to_iso8601()

    to_form(%{"datetime" => value}, as: :time_edit)
  end

  defp download_names(images) do
    images
    |> Enum.with_index(1)
    |> Map.new(fn {image, index} -> {image.public_id, download_name(image, index)} end)
  end

  defp download_name(image, index) do
    number = String.pad_leading(to_string(index), 4, "0")
    time = Calendar.strftime(image.effective_taken_at, "%Y%m%d-%H%M%S")
    "#{number}-#{time}-#{Media.sanitize_filename(image.original_filename)}"
  end
end
