// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/imaedge"
import topbar from "../vendor/topbar"
import {GalleryActions} from "./gallery_actions"
import {UploadQueue} from "./upload_queue"

function installCollectionNamePrompts() {
  document.querySelectorAll("form[data-collection-name-form]").forEach(form => {
    if (form.dataset.collectionNamePromptBound === "true") return
    form.dataset.collectionNamePromptBound = "true"

    form.addEventListener("submit", event => {
      const input = form.querySelector("input[name='name']")
      if (!input || input.value.trim()) return

      const value = window.prompt("Name this collection", "")
      if (value === null) {
        event.preventDefault()
        return
      }

      const trimmed = value.trim()
      if (!trimmed) {
        event.preventDefault()
        return
      }

      input.value = trimmed.slice(0, 80)
    })
  })
}

const ShareCollectionLink = {
  mounted() {
    this.el.addEventListener("click", async () => {
      const url = this.el.dataset.collectionUrl || window.location.href
      const title = this.el.dataset.collectionTitle || "imaedge collection"
      const label = this.el.querySelector("span")
      const original = label ? label.textContent : null

      try {
        if (!navigator.share) throw new Error("browser_share_unavailable")

        await navigator.share({
          title,
          text: "Add original photos to this imaedge collection.",
          url,
        })
      } catch (err) {
        if (err && err.name === "AbortError") return
        await copyText(url)
        if (label) {
          label.textContent = "link copied"
          setTimeout(() => { if (original !== null) label.textContent = original }, 1400)
        }
      }
    })
  },
}

async function copyText(value) {
  try {
    await navigator.clipboard.writeText(value)
  } catch (_err) {
    const helper = document.createElement("textarea")
    helper.value = value
    helper.style.position = "fixed"
    helper.style.opacity = "0"
    document.body.appendChild(helper)
    helper.select()
    try { document.execCommand("copy") } catch (_e) {}
    document.body.removeChild(helper)
  }
}

installCollectionNamePrompts()
window.addEventListener("phx:page-loading-stop", installCollectionNamePrompts)

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, GalleryActions, UploadQueue, ShareCollectionLink},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
