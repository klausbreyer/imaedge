defmodule ImaedgeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ImaedgeWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="site-header">
      <a href={~p"/"} class="brand-mark">
        <span class="brand-dot"></span> imaedge
      </a>
      <div class="header-rule"></div>
    </header>

    <main class="site-main">
      <div class="site-frame">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the workspace shell used by the collection and export pages.

  Provides the brand top nav, paper background, Satoshi typography, and a
  centered main content frame. The optional `live` and `identity` props
  drive the small status pill next to the brand mark.
  """
  attr :flash, :map, required: true
  attr :live?, :boolean, default: false
  attr :identity, :string, default: nil
  attr :show_new_collection, :boolean, default: true

  slot :inner_block, required: true

  def workspace(assigns) do
    ~H"""
    <div class="font-brand-sans text-ink text-[15.5px] leading-[1.55] tracking-[-0.01em] bg-paper min-h-screen antialiased selection:bg-brand-accent selection:text-ink">
      <header class="sticky top-0 z-50 bg-paper/85 backdrop-blur-md backdrop-saturate-150 border-b border-black/[0.06]">
        <div class="max-w-[1320px] mx-auto px-8 max-md:px-4 max-[460px]:px-3 flex items-center justify-between h-20 max-md:h-14 gap-6">
          <a
            class="inline-flex items-center gap-3 max-md:gap-2 font-bold text-[26px] max-md:text-[20px] tracking-[-0.025em] text-ink"
            href={~p"/"}
            aria-label="imaedge"
          >
            <svg class="w-10 h-10 max-md:w-7 max-md:h-7 block" viewBox="0 0 64 64" aria-hidden="true">
              <path
                d="M 14 4 H 50 a 10 10 0 0 1 10 10 V 36 L 36 60 H 14 a 10 10 0 0 1 -10 -10 V 14 a 10 10 0 0 1 10 -10 Z"
                fill="#0a0a0a"
              />
              <path d="M 60 36 L 36 60 L 36 56.8 L 56.8 36 Z" fill="#22d3ee" />
              <text
                x="30"
                y="45"
                text-anchor="middle"
                font-family="ui-sans-serif, system-ui, -apple-system, 'SF Pro Display', 'Helvetica Neue', Inter, Arial, sans-serif"
                font-size="44"
                font-weight="800"
                fill="#fafaf7"
              >
                æ
              </text>
            </svg>
            <span class="brand-wm">im<em>æ</em>dge</span>
          </a>

          <div class="inline-flex items-center gap-[18px]">
            <.start_collection_cta
              :if={@show_new_collection}
              href={~p"/"}
            />
          </div>
        </div>
      </header>

      <main>
        {render_slot(@inner_block)}
      </main>

      <footer class="max-w-[1320px] mx-auto px-8 max-md:px-3 max-[460px]:px-2.5 pt-8 pb-10 max-md:pt-3 max-md:pb-4 border-t border-black/[0.06] mt-[clamp(32px,4vw,56px)] max-md:mt-3 flex items-center justify-between gap-3 font-brand-sans text-[12px] max-md:text-[11px] text-mid tracking-[-0.005em]">
        <span>Images. Together. At The Edge.</span>
        <a href={~p"/"} class="hover:text-ink transition-colors">© 2026 imaedge</a>
      </footer>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders the marketing shell used by `/`, `/about` and `/privacy`.

  Wraps the page content in the shared experiment banner, sticky brand header
  and full footer with About, Source and policy links.
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def marketing_shell(assigns) do
    ~H"""
    <div class="font-brand-sans text-ink text-[16px] leading-[1.55] tracking-[-0.01em] bg-paper antialiased overflow-x-hidden selection:bg-brand-accent selection:text-ink">
      <div class="bg-ink text-paper border-b border-black/[0.06] text-[13px] max-md:text-[12px] font-semibold tracking-[-0.005em] uppercase">
        <div class="max-w-[1320px] mx-auto px-8 max-md:px-4 max-[460px]:px-3 py-2 max-md:py-1.5 flex items-center justify-center gap-2 flex-wrap text-center">
          <span>this is an experiment. it is free, but also without any guarantee.</span>
        </div>
      </div>

      <header class="sticky top-0 z-50 bg-paper/85 backdrop-blur-md backdrop-saturate-150 border-b border-black/[0.06]">
        <div class="max-w-[1320px] mx-auto px-8 max-md:px-4 max-[460px]:px-3 flex items-center justify-between h-20 max-md:h-14 gap-6">
          <a
            class="inline-flex items-center gap-3 max-md:gap-2 font-bold text-[26px] max-md:text-[20px] tracking-[-0.025em] text-ink"
            href={~p"/"}
            aria-label="imaedge"
          >
            <svg class="w-10 h-10 max-md:w-7 max-md:h-7 block" viewBox="0 0 64 64" aria-hidden="true">
              <path
                d="M 14 4 H 50 a 10 10 0 0 1 10 10 V 36 L 36 60 H 14 a 10 10 0 0 1 -10 -10 V 14 a 10 10 0 0 1 10 -10 Z"
                fill="#0a0a0a"
              />
              <path d="M 60 36 L 36 60 L 36 56.8 L 56.8 36 Z" fill="#22d3ee" />
              <text
                x="30"
                y="45"
                text-anchor="middle"
                font-family="ui-sans-serif, system-ui, -apple-system, 'SF Pro Display', 'Helvetica Neue', Inter, Arial, sans-serif"
                font-size="44"
                font-weight="800"
                fill="#fafaf7"
              >
                æ
              </text>
            </svg>
            <span class="brand-wm">im<em>æ</em>dge</span>
          </a>
          <nav class="inline-flex items-center gap-7 max-md:gap-3 font-brand-sans text-[14px] text-mid tracking-[-0.005em]">
            <a class="transition-colors hover:text-ink max-md:hidden" href={~p"/#how"}>
              how it works
            </a>
            <a class="transition-colors hover:text-ink max-md:hidden" href={~p"/#faq"}>
              questions
            </a>
            <form
              action={~p"/collections"}
              method="post"
              class="inline-flex"
              data-collection-name-form
            >
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
              <input type="hidden" name="name" value="" />
              <.start_collection_cta />
            </form>
          </nav>
        </div>
      </header>

      <main>
        {render_slot(@inner_block)}

        <footer class="max-w-[1320px] mx-auto px-8 max-md:px-4 max-[460px]:px-3 pt-12 max-md:pt-8 pb-9 max-md:pb-6 border-t border-black/[0.06] grid grid-cols-[1.4fr_1fr_1fr_1fr] gap-9 max-[760px]:grid-cols-2 max-[760px]:gap-7">
          <div>
            <a
              class="inline-flex items-center gap-2.5 font-bold text-[18px] tracking-[-0.025em] text-ink"
              href={~p"/"}
              aria-label="imaedge"
            >
              <svg class="w-6 h-6 block" viewBox="0 0 64 64" aria-hidden="true">
                <path
                  d="M 14 4 H 50 a 10 10 0 0 1 10 10 V 36 L 36 60 H 14 a 10 10 0 0 1 -10 -10 V 14 a 10 10 0 0 1 10 -10 Z"
                  fill="#0a0a0a"
                />
                <path d="M 60 36 L 36 60 L 36 56.8 L 56.8 36 Z" fill="#22d3ee" />
                <text
                  x="30"
                  y="45"
                  text-anchor="middle"
                  font-family="ui-sans-serif, system-ui, -apple-system, 'SF Pro Display', 'Helvetica Neue', Inter, Arial, sans-serif"
                  font-size="44"
                  font-weight="800"
                  fill="#fafaf7"
                >
                  æ
                </text>
              </svg>
              <span class="brand-wm">im<em>æ</em>dge</span>
            </a>
            <p class="text-[14px] text-mid leading-[1.5] max-w-[32ch] mt-3">
              A small upload room for when several phones have to sync on bad reception.
            </p>
          </div>
          <div>
            <h4 class="font-brand-sans text-[13px] font-bold text-ink mb-3.5 tracking-[-0.01em]">
              Product
            </h4>
            <ul class="list-none flex flex-col gap-2">
              <li>
                <form action={~p"/collections"} method="post" class="inline">
                  <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
                  <button
                    type="submit"
                    class="text-ink-2 text-[14px] transition-colors hover:text-ink cursor-pointer bg-transparent p-0 border-0 font-inherit"
                  >
                    Start a Collection
                  </button>
                </form>
              </li>
              <li>
                <a class="text-ink-2 text-[14px] transition-colors hover:text-ink" href={~p"/#how"}>
                  How It Works
                </a>
              </li>
              <li>
                <a class="text-ink-2 text-[14px] transition-colors hover:text-ink" href={~p"/#faq"}>
                  Questions
                </a>
              </li>
            </ul>
          </div>
          <div>
            <h4 class="font-brand-sans text-[13px] font-bold text-ink mb-3.5 tracking-[-0.01em]">
              About
            </h4>
            <ul class="list-none flex flex-col gap-2">
              <li>
                <a class="text-ink-2 text-[14px] transition-colors hover:text-ink" href={~p"/about"}>
                  About
                </a>
              </li>
              <li>
                <a
                  class="text-ink-2 text-[14px] transition-colors hover:text-ink"
                  href={~p"/privacy"}
                >
                  Privacy
                </a>
              </li>
              <li>
                <a
                  class="text-ink-2 text-[14px] transition-colors hover:text-ink"
                  href="https://v01.io"
                >
                  v01.io
                </a>
              </li>
              <li>
                <a
                  class="text-ink-2 text-[14px] transition-colors hover:text-ink"
                  href="mailto:kb@v01.io"
                >
                  kb@v01.io
                </a>
              </li>
            </ul>
          </div>
          <div>
            <h4 class="font-brand-sans text-[13px] font-bold text-ink mb-3.5 tracking-[-0.01em]">
              Source
            </h4>
            <ul class="list-none flex flex-col gap-2">
              <li>
                <a
                  class="text-ink-2 text-[14px] transition-colors hover:text-ink"
                  href="https://github.com/klausbreyer/imaedge"
                >
                  imaedge on GitHub
                </a>
              </li>
              <li>
                <a
                  class="text-ink-2 text-[14px] transition-colors hover:text-ink"
                  href="https://github.com/klausbreyer/imaedge-gallery-wp-importer"
                >
                  WordPress importer
                </a>
              </li>
            </ul>
          </div>

          <div class="col-span-full mt-9 max-md:mt-6 pt-5 max-md:pt-4 border-t border-black/[0.06] flex items-center justify-between gap-4 flex-wrap font-brand-sans text-[13px] max-md:text-[12px] text-mid tracking-[-0.005em]">
            <span>Images. Together. At The Edge.</span>
            <a href={~p"/"} class="hover:text-ink transition-colors">© 2026 imaedge</a>
          </div>
        </footer>
      </main>
    </div>

    <Layouts.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
