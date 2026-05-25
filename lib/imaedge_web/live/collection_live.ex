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
    <Layouts.workspace flash={@flash} live?={true}>
      <section class="max-w-[1320px] mx-auto px-8 max-md:px-3 max-[460px]:px-2.5 py-[clamp(56px,7vw,96px)] pb-[clamp(56px,6vw,88px)] max-md:py-[32px] max-md:pb-[40px] max-[460px]:py-[28px] max-[460px]:pb-[36px]">
        <div class="font-brand-sans text-[13px] text-mid mb-4 tracking-[-0.005em] brand-reveal opacity-0 translate-y-2 motion-safe:animate-rise max-md:mb-3">
          collection
        </div>

        <h1 class="font-brand-sans font-bold text-[clamp(32px,5.8vw,68px)] max-md:text-[36px] max-[460px]:text-[30px] leading-none tracking-[-0.035em] max-md:tracking-[-0.03em] text-ink break-all [overflow-wrap:anywhere] brand-reveal opacity-0 translate-y-2 motion-safe:animate-rise">
          {@collection.public_id}
        </h1>

        <div class="flex flex-wrap items-center gap-x-3 gap-y-6 mt-9 max-md:gap-x-2 max-md:gap-y-[18px] max-md:mt-6 brand-reveal opacity-0 translate-y-2 motion-safe:animate-rise">
          <button
            type="button"
            id="copy-collection-link"
            phx-hook="CopyCollectionLink"
            data-collection-url={url(~p"/i/#{@collection.public_id}")}
            class="inline-flex items-center gap-2.5 px-3.5 py-2.5 bg-white border border-ink rounded-[3px] font-medium text-[13.5px] max-md:text-[13px] text-ink transition-colors hover:bg-ink hover:text-paper cursor-pointer"
            aria-label="copy collection link"
          >
            <svg
              class="w-3.5 h-3.5 stroke-current stroke-[1.8] fill-none"
              viewBox="0 0 24 24"
            >
              <path d="M9 9h10v10H9zM5 5h10v10" />
            </svg>
            <span>copy link</span>
          </button>

          <a
            class="inline-flex items-center gap-2.5 px-3.5 py-2.5 bg-white border border-ink rounded-[3px] font-medium text-[13.5px] max-md:text-[13px] text-ink transition-colors hover:bg-ink hover:text-paper"
            href={~p"/i/#{@collection.public_id}/export"}
          >
            <svg
              class="w-3.5 h-3.5 stroke-current stroke-[1.8] fill-none"
              viewBox="0 0 24 24"
            >
              <path d="M5 12v6a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-6M12 3v12m-5-5 5 5 5-5" />
            </svg>
            <span>export HTML</span>
          </a>

          <div class="ml-auto max-[760px]:ml-0 max-[760px]:w-full max-[760px]:flex-wrap max-[760px]:gap-[18px] max-[760px]:pt-2.5 inline-flex gap-7 font-brand-sans text-[13.5px] text-mid tracking-[-0.005em]">
            <div class="inline-flex items-baseline gap-1.5">
              <span class="font-brand-sans font-bold text-[22px] max-md:text-[18px] text-ink tracking-[-0.03em] mr-2 max-md:mr-1">
                {@image_count}
              </span>
              <span>images</span>
            </div>
            <div class="inline-flex items-baseline gap-1.5">
              <span class="font-brand-sans font-bold text-[22px] max-md:text-[18px] text-ink tracking-[-0.03em] mr-2 max-md:mr-1">
                {@upload_count}
              </span>
              <span>processing</span>
            </div>
          </div>
        </div>
      </section>

      <section class="max-w-[1320px] mx-auto px-8 max-md:px-3 max-[460px]:px-2.5">
        <div class="grid grid-cols-[1fr_1.6fr] gap-14 pb-[clamp(40px,5vw,64px)] max-[980px]:grid-cols-1 max-[980px]:gap-12">

          <div
            id="upload-queue"
            phx-hook="UploadQueue"
            phx-update="ignore"
            data-collection-id={@collection.public_id}
            class="brand-reveal opacity-0 translate-y-2 motion-safe:animate-rise max-[980px]:pb-10 max-[980px]:border-b max-[980px]:border-black/[0.06]"
          >
            <div id="upload" class="flex items-baseline justify-between gap-4 mb-[18px] max-md:mb-4">
              <h3 class="font-bold text-[22px] max-md:text-[20px] tracking-[-0.025em] leading-tight">
                Uploads
              </h3>
              <div id="queue-waiting" class="font-brand-sans text-[13px] text-mid tracking-[-0.005em]">
                0 waiting
              </div>
            </div>

            <div class="relative border-[1.5px] border-dashed border-black/[0.20] rounded-[4px] bg-white hover:border-ink hover:bg-brand-accent/[0.04] transition-[border-color,background]">
              <label
                for="image-picker"
                class="block p-5 max-md:p-[18px] flex flex-col gap-3.5 items-start cursor-pointer"
              >
                <div class="w-10 h-10 rounded-[3px] bg-ink text-paper grid place-items-center" aria-hidden="true">
                  <svg class="w-[18px] h-[18px] stroke-current stroke-[1.7] fill-none" viewBox="0 0 24 24">
                    <path
                      d="M12 16V4m0 0-4 4m4-4 4 4M5 20h14"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                </div>
                <div class="font-bold text-[17px] max-md:text-[15px] tracking-[-0.02em]">
                  Drop images here, or select
                </div>
              </label>
              <div class="flex items-center justify-between gap-4 px-5 max-md:px-[18px] pb-4 max-md:pb-[14px] -mt-1 font-brand-sans text-[13px] text-mid tracking-[-0.005em]">
                <span class="inline-flex items-center gap-1.5">
                  <label for="upload-concurrency">parallel</label>
                  <select
                    id="upload-concurrency"
                    aria-label="parallel uploads"
                    class="font-inherit text-ink bg-paper border border-black/[0.08] rounded-[3px] py-1 pr-1.5 pl-2"
                  >
                    <option value="1" selected>1</option>
                    <option value="2">2</option>
                    <option value="3">3</option>
                  </select>
                </span>
                <span>jpeg · png · webp</span>
              </div>
              <input
                id="image-picker"
                type="file"
                accept="image/jpeg,image/png,image/webp"
                multiple
                class="hidden"
              />
            </div>

            <div id="client-queue" class="mt-3 flex flex-col gap-2.5">
              <div class="text-[14px] text-mid py-3 px-3.5 bg-tint rounded-[3px]">
                Nothing waiting locally.
              </div>
            </div>

            <div class="mt-4 flex items-center gap-3 py-2.5 border-t border-b border-black/[0.06] font-brand-sans text-[13.5px] text-mid">
              <span class="font-brand-sans font-bold text-[13px] text-ink py-[3px] px-2.5 bg-tint rounded-[3px] tracking-[-0.01em]">
                {@upload_count}
              </span>
              <span>
                <strong class="font-bold text-ink tracking-[-0.015em]">Processing.</strong>
                Ingest jobs read previews and EXIF here.
              </span>
            </div>

            <div
              id="server-upload-list"
              phx-update="stream"
              class="mt-3 flex flex-col gap-2.5"
            >
              <article
                :for={{dom_id, upload} <- @streams.uploads}
                id={dom_id}
                class="flex flex-wrap gap-3 items-center justify-between bg-white border border-black/[0.06] rounded-[3px] py-2.5 px-3 font-brand-sans text-[13.5px]"
              >
                <div class="min-w-0 flex-1">
                  <strong class="block font-medium text-ink truncate">
                    {upload.original_filename}
                  </strong>
                  <span class="font-brand-mono text-[11.5px] text-mid">
                    {upload.status}
                  </span>
                  <code
                    :if={upload.error_message}
                    class="block mt-1 font-brand-mono text-[11.5px] text-warn break-all"
                  >
                    {upload.error_message}
                  </code>
                </div>
                <div :if={upload.status == "failed"} class="flex gap-1.5">
                  <button
                    type="button"
                    phx-click="retry_upload"
                    phx-value-id={upload.public_id}
                    class="px-2.5 py-1.5 border border-ink rounded-[3px] text-[12.5px] hover:bg-ink hover:text-paper"
                  >
                    retry
                  </button>
                  <button
                    type="button"
                    phx-click="remove_upload"
                    phx-value-id={upload.public_id}
                    class="px-2.5 py-1.5 border border-black/[0.20] rounded-[3px] text-[12.5px] text-mid hover:border-warn hover:text-warn"
                  >
                    remove
                  </button>
                </div>
              </article>
            </div>

            <div class="mt-4" aria-label="local storage estimate">
              <div class="flex justify-between gap-3 font-brand-sans text-[13px] text-mid mb-2 tracking-[-0.005em]">
                <span>local browser storage</span>
                <span id="storage-estimate">estimate pending</span>
              </div>
              <div class="h-1 bg-tint overflow-hidden">
                <div id="storage-bar" class="block h-full bg-ink w-0"></div>
              </div>
            </div>
          </div>

          <div class="flex flex-col gap-8 max-[980px]:gap-7 min-w-0">

            <div class="brand-reveal opacity-0 translate-y-2 motion-safe:animate-rise">
              <div class="flex items-baseline justify-between gap-4 mb-4 max-md:mb-3">
                <h3 class="font-bold text-[22px] max-md:text-[20px] tracking-[-0.025em]">
                  Gallery
                </h3>
              </div>

              <div :if={@undo_image} class="flex items-center justify-between gap-3 mb-3 py-2.5 px-3 bg-tint rounded-[3px] font-brand-sans text-[13px] text-mid">
                <span>Image hidden for 10 seconds.</span>
                <button
                  type="button"
                  phx-click="undo_delete"
                  phx-value-id={@undo_image.public_id}
                  class="px-2.5 py-1.5 border border-ink rounded-[3px] text-ink text-[12.5px] hover:bg-ink hover:text-paper"
                >
                  undo
                </button>
              </div>

              <div :if={@editing_image} class="fixed inset-0 z-40 grid items-end md:items-center p-4">
                <button
                  type="button"
                  class="absolute inset-0 w-full h-full bg-black/[0.55] border-0 cursor-pointer"
                  phx-click="close_time_editor"
                  title="Close"
                >
                </button>
                <div class="relative w-[min(100%,520px)] mx-auto bg-paper border border-black/[0.08] rounded-[3px] p-4 shadow-[0_22px_70px_rgba(10,10,10,0.34)]">
                  <div class="grid grid-cols-[58px_minmax(0,1fr)_42px] gap-2.5 items-center mb-3">
                    <img
                      src={@editing_image.preview_small_url || @editing_image.original_url}
                      alt={@editing_image.original_filename}
                      class="w-[58px] h-[58px] object-cover border border-black/[0.08] bg-tint"
                    />
                    <div class="min-w-0">
                      <p class="font-brand-mono text-[11px] text-mid uppercase tracking-[0.06em] mb-1">
                        album time
                      </p>
                      <strong class="block font-brand-mono text-[13px] text-mid truncate">
                        {@editing_image.contributor_id}
                      </strong>
                    </div>
                    <button
                      type="button"
                      title="Close"
                      phx-click="close_time_editor"
                      class="inline-flex h-[42px] items-center justify-center border border-ink rounded-[3px] bg-ink text-paper cursor-pointer"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>

                  <.form
                    for={time_form(@editing_image)}
                    id={"time-overlay-form-#{@editing_image.public_id}"}
                    phx-submit="set_time"
                    class="grid gap-2.5"
                  >
                    <input type="hidden" name="image-id" value={@editing_image.public_id} />
                    <.input
                      field={time_form(@editing_image)[:datetime]}
                      type="datetime-local"
                      label="Album time"
                      step="1"
                    />
                    <button
                      type="submit"
                      class="inline-flex min-h-[42px] items-center justify-center bg-ink text-paper border border-ink rounded-[3px] font-medium text-[13.5px] cursor-pointer hover:bg-[#1a1a1a]"
                    >
                      save time
                    </button>
                  </.form>
                </div>
              </div>

              <div
                id="gallery-grid"
                phx-update="stream"
                phx-hook="GalleryActions"
                class="grid grid-cols-3 gap-3 max-[760px]:grid-cols-4 max-[760px]:gap-[2px] max-[760px]:-mx-3 max-[460px]:-mx-2.5"
              >
                <figure
                  :for={{dom_id, image} <- @streams.images}
                  id={dom_id}
                  class="brand-tile relative flex flex-col gap-0"
                  data-editing-time={@editing_time_id == image.public_id}
                >
                  <div class="brand-tile-img relative aspect-square overflow-hidden rounded-[2px] max-[760px]:rounded-none bg-tint">
                    <a href={image.preview_large_url || image.original_url} class="block w-full h-full">
                      <img
                        class="w-full h-full object-cover transition-transform duration-[600ms] ease-out"
                        src={image.preview_small_url || image.original_url}
                        loading="lazy"
                        alt={image.original_filename}
                      />
                    </a>
                    <span class="absolute left-1.5 top-1.5 max-md:left-[3px] max-md:top-[3px] py-[3px] px-[7px] max-md:py-0.5 max-md:px-[5px] max-w-[calc(100%-12px)] max-md:max-w-[calc(100%-6px)] bg-black/[0.42] backdrop-blur-md text-white font-brand-mono text-[10.5px] max-md:text-[9.5px] rounded-[2px] tracking-[0.01em] whitespace-nowrap overflow-hidden text-ellipsis">
                      {image.contributor_id}
                    </span>
                    <div
                      class="brand-tools absolute left-0 right-0 bottom-0 flex gap-px"
                      role="toolbar"
                      aria-label="image actions"
                    >
                      <button
                        type="button"
                        class="flex-1 h-[34px] max-md:h-[30px] grid place-items-center bg-black/[0.38] text-white transition-colors backdrop-blur-md hover:bg-black/[0.78] cursor-pointer"
                        aria-label="move earlier"
                        phx-click="move"
                        phx-value-id={image.public_id}
                        phx-value-direction="earlier"
                      >
                        <svg
                          class="w-[15px] h-[15px] max-md:w-[13px] max-md:h-[13px] stroke-current stroke-[1.8] fill-none"
                          viewBox="0 0 24 24"
                        >
                          <path
                            d="M15 18l-6-6 6-6"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                          />
                        </svg>
                      </button>
                      <button
                        type="button"
                        class="flex-1 h-[34px] max-md:h-[30px] grid place-items-center bg-black/[0.38] text-white transition-colors backdrop-blur-md hover:bg-black/[0.78] cursor-pointer"
                        aria-label="move later"
                        phx-click="move"
                        phx-value-id={image.public_id}
                        phx-value-direction="later"
                      >
                        <svg
                          class="w-[15px] h-[15px] max-md:w-[13px] max-md:h-[13px] stroke-current stroke-[1.8] fill-none"
                          viewBox="0 0 24 24"
                        >
                          <path
                            d="M9 18l6-6-6-6"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                          />
                        </svg>
                      </button>
                      <button
                        type="button"
                        class="flex-1 h-[34px] max-md:h-[30px] grid place-items-center bg-black/[0.38] text-white transition-colors backdrop-blur-md hover:bg-black/[0.78] cursor-pointer"
                        aria-label="edit album time"
                        phx-click="edit_time"
                        phx-value-id={image.public_id}
                      >
                        <svg
                          class="w-[15px] h-[15px] max-md:w-[13px] max-md:h-[13px] stroke-current stroke-[1.8] fill-none"
                          viewBox="0 0 24 24"
                        >
                          <path
                            d="M7 4v3M17 4v3M4 9h16M5 6h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1z"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                          />
                        </svg>
                      </button>
                      <button
                        type="button"
                        class="flex-1 h-[34px] max-md:h-[30px] grid place-items-center bg-black/[0.38] text-white transition-colors backdrop-blur-md hover:bg-[rgba(226,106,72,0.85)] cursor-pointer"
                        aria-label="delete"
                        data-delete-id={image.public_id}
                        data-confirm-message="Delete this image?"
                      >
                        <svg
                          class="w-[15px] h-[15px] max-md:w-[13px] max-md:h-[13px] stroke-current stroke-[1.8] fill-none"
                          viewBox="0 0 24 24"
                        >
                          <path
                            d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                          />
                        </svg>
                      </button>
                    </div>
                  </div>
                  <figcaption class="flex flex-col gap-0 pt-2.5 max-md:px-[5px] max-md:pt-2 max-md:pb-1 font-brand-sans text-[13px] max-md:text-[11.5px] leading-[1.4] max-md:leading-[1.35] text-mid tracking-[-0.005em]">
                    <span class="text-ink font-semibold">
                      {format_album_date(image.effective_taken_at, image.timezone_offset_minutes)}
                    </span>
                    <time class="text-mid [font-feature-settings:'tnum']">
                      {format_album_clock(image.effective_taken_at, image.timezone_offset_minutes)}
                    </time>
                  </figcaption>
                </figure>
              </div>
            </div>

          </div>
        </div>
      </section>

      <section class="max-w-[1320px] mx-auto px-8 max-md:px-3 max-[460px]:px-2.5 pb-[clamp(40px,5vw,64px)]">
        <details class="brand-debug font-brand-sans text-[13px]">
          <summary class="cursor-pointer text-mid inline-flex items-center gap-2 py-1.5 tracking-[-0.005em]">
            debug log
          </summary>
          <div class="mt-2 flex gap-2 text-[12px] text-mid">
            <button
              id="copy-debug-log"
              type="button"
              class="px-2 py-1 border border-black/[0.08] rounded-[3px] hover:border-ink hover:text-ink"
            >
              copy
            </button>
            <button
              id="clear-debug-log"
              type="button"
              class="px-2 py-1 border border-black/[0.08] rounded-[3px] hover:border-ink hover:text-ink"
            >
              clear
            </button>
          </div>
          <pre id="debug-log-output" class="mt-2.5 py-3 px-3.5 bg-tint text-ink-2 rounded-[3px] font-brand-mono text-[11.5px] leading-[1.6] max-h-[180px] overflow-auto whitespace-pre-wrap"></pre>
        </details>
      </section>
    </Layouts.workspace>
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

  defp format_album_date(datetime, offset_minutes) do
    datetime
    |> shift_to_album_offset(offset_minutes)
    |> Calendar.strftime("%Y-%m-%d")
  end

  defp format_album_clock(datetime, offset_minutes) do
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
