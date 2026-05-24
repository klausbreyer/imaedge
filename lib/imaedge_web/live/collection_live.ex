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
     |> assign(:editing_time_id, nil)
     |> assign(:undo_image, nil)
     |> reload()}
  end

  def handle_event("move", %{"id" => image_id, "direction" => direction}, socket) do
    Media.move_image(socket.assigns.collection, image_id, direction)
    {:noreply, reload(socket)}
  end

  def handle_event("edit_time", %{"id" => image_id}, socket) do
    editing_time_id =
      if socket.assigns.editing_time_id == image_id do
        nil
      else
        image_id
      end

    {:noreply, socket |> assign(:editing_time_id, editing_time_id) |> reload()}
  end

  def handle_event("close_time_editor", _params, socket) do
    {:noreply, socket |> assign(:editing_time_id, nil) |> reload()}
  end

  def handle_event(
        "set_time",
        %{"image-id" => image_id, "time_edit" => %{"datetime" => value}},
        socket
      ) do
    case Media.update_effective_time(socket.assigns.collection, image_id, value) do
      {:ok, _image} -> {:noreply, socket |> assign(:editing_time_id, nil) |> reload()}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Could not update time")}
    end
  end

  def handle_event("delete", %{"id" => image_id}, socket) do
    case Media.mark_pending_delete(socket.assigns.collection, image_id) do
      {:ok, image} ->
        {:noreply, socket |> assign(:undo_image, image) |> reload()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete image")}
    end
  end

  def handle_event("undo_delete", %{"id" => image_id}, socket) do
    case Media.undo_delete(socket.assigns.collection, image_id) do
      {:ok, _image} ->
        {:noreply, socket |> assign(:undo_image, nil) |> reload()}

      {:error, _reason} ->
        {:noreply,
         socket |> assign(:undo_image, nil) |> put_flash(:error, "Could not undo delete")}
    end
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

        <div :if={@undo_image} class="undo-delete">
          <span>Image hidden for 10 seconds.</span>
          <button
            type="button"
            phx-click="undo_delete"
            phx-value-id={@undo_image.public_id}
          >
            Undo
          </button>
        </div>

        <div :if={@editing_image} class="time-editor-overlay">
          <button
            type="button"
            class="time-editor-backdrop"
            title="Close"
            phx-click="close_time_editor"
          >
          </button>
          <div class="time-editor-card">
            <div class="time-editor-head">
              <img
                src={@editing_image.preview_small_url || @editing_image.original_url}
                alt={@editing_image.original_filename}
              />
              <div>
                <p class="eyebrow">album time</p>
                <strong>{@editing_image.contributor_id}</strong>
              </div>
              <button type="button" title="Close" phx-click="close_time_editor">
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <.form
              for={time_form(@editing_image)}
              id={"time-overlay-form-#{@editing_image.public_id}"}
              phx-submit="set_time"
            >
              <input type="hidden" name="image-id" value={@editing_image.public_id} />
              <.input
                field={time_form(@editing_image)[:datetime]}
                type="datetime-local"
                label="Album time"
                step="1"
              />
              <button type="submit">Save time</button>
            </.form>
          </div>
        </div>

        <div id="gallery-grid" phx-update="stream" phx-hook="GalleryActions" class="gallery-grid">
          <div class="empty-state hidden only:block">No images yet.</div>
          <article
            :for={{dom_id, image} <- @streams.images}
            id={dom_id}
            class="image-tile"
            data-editing-time={@editing_time_id == image.public_id}
          >
            <a href={image.preview_large_url || image.original_url} class="image-preview">
              <img
                src={image.preview_small_url || image.original_url}
                loading="lazy"
                alt={image.original_filename}
              />
            </a>

            <div class="tile-meta">
              <span>{image.contributor_id}</span>
              <span
                class="tile-time"
                data-mobile-date={
                  format_compact_date(
                    image.effective_taken_at,
                    image.timezone_offset_minutes
                  )
                }
                data-mobile-time={
                  format_compact_clock(
                    image.effective_taken_at,
                    image.timezone_offset_minutes
                  )
                }
              >
                {format_time(image.effective_taken_at, image.timezone_offset_minutes)}
              </span>
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
              <button
                type="button"
                title="Edit album time"
                phx-click="edit_time"
                phx-value-id={image.public_id}
              >
                <.icon name="hero-calendar-days" class="size-4" />
              </button>
              <button
                type="button"
                title="Delete"
                data-delete-id={image.public_id}
                data-confirm-message="Delete this image?"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp reload(socket) do
    images = Media.list_gallery_images(socket.assigns.collection)
    uploads = Media.list_visible_uploads(socket.assigns.collection)
    editing_image = Enum.find(images, &(&1.public_id == socket.assigns.editing_time_id))

    socket
    |> assign(:image_count, length(images))
    |> assign(:upload_count, length(uploads))
    |> assign(:editing_image, editing_image)
    |> stream(:images, images, reset: true)
    |> stream(:uploads, uploads, reset: true)
  end

  defp format_time(datetime, offset_minutes) do
    datetime
    |> shift_to_album_offset(offset_minutes)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_compact_date(datetime, offset_minutes) do
    datetime
    |> shift_to_album_offset(offset_minutes)
    |> Calendar.strftime("%m-%d")
  end

  defp format_compact_clock(datetime, offset_minutes) do
    datetime
    |> shift_to_album_offset(offset_minutes)
    |> Calendar.strftime("%H:%M")
  end

  defp time_form(image) do
    value =
      image.effective_taken_at
      |> shift_to_album_offset(image.timezone_offset_minutes)
      |> Calendar.strftime("%Y-%m-%dT%H:%M:%S")

    to_form(%{"datetime" => value}, as: :time_edit)
  end

  defp shift_to_album_offset(datetime, offset_minutes) when is_integer(offset_minutes) do
    DateTime.add(datetime, offset_minutes * 60, :second)
  end

  defp shift_to_album_offset(datetime, _offset_minutes), do: datetime
end
