const DRAG_THRESHOLD = 6
const SWIPE_THRESHOLD = 48
const TOUCH_DRAG_DELAY_MS = 180

export const GalleryActions = {
  mounted() {
    this.dragged = null
    this.pointerDrag = null
    this.initialOrder = []
    this.suppressClickUntil = 0
    this.restoreScrollY = null
    this.lightboxIndex = 0
    this.lightboxLoadToken = 0
    this.touchStart = null

    this.lightbox = document.querySelector("#gallery-lightbox")
    this.lightboxImage = this.lightbox?.querySelector("[data-lightbox-image]")
    this.lightboxLoading = this.lightbox?.querySelector("[data-lightbox-loading]")
    this.lightboxOriginal = this.lightbox?.querySelector("[data-lightbox-original]")
    this.lightboxCount = this.lightbox?.querySelector("[data-lightbox-count]")
    this.lightboxCaption = this.lightbox?.querySelector("[data-lightbox-caption]")
    this.lightboxDate = this.lightbox?.querySelector("[data-lightbox-date]")
    this.lightboxStage = this.lightbox?.querySelector("[data-lightbox-stage]")

    this.el.addEventListener("click", event => this.handleClick(event))
    this.el.addEventListener("change", event => this.handleTimeChange(event))
    this.el.addEventListener("dragstart", event => this.handleDragStart(event))
    this.el.addEventListener("dragover", event => this.handleDragOver(event))
    this.el.addEventListener("drop", event => this.handleDrop(event))
    this.el.addEventListener("dragend", () => this.finishReorder())
    this.el.addEventListener("pointerdown", event => this.handlePointerDown(event))
    this.el.addEventListener("pointermove", event => this.handlePointerMove(event))
    this.el.addEventListener("pointerup", event => this.handlePointerUp(event))
    this.el.addEventListener("pointercancel", event => this.handlePointerUp(event))

    if (this.lightbox) {
      this.lightbox.addEventListener("click", event => this.handleLightboxClick(event))
      this.lightbox.addEventListener("cancel", event => {
        event.preventDefault()
        this.closeLightbox()
      })
      this.lightbox.addEventListener("close", () => this.resetLightbox())
      this.lightboxStage.addEventListener("touchstart", event => this.handleTouchStart(event), {passive: true})
      this.lightboxStage.addEventListener("touchend", event => this.handleTouchEnd(event), {passive: true})
    }

    this.boundKeydown = event => this.handleKeydown(event)
    window.addEventListener("keydown", this.boundKeydown)
  },

  updated() {
    if (this.restoreScrollY !== null) this.restoreScroll()
  },

  destroyed() {
    window.removeEventListener("keydown", this.boundKeydown)
    if (this.pointerDrag?.timer) window.clearTimeout(this.pointerDrag.timer)
    this.resetLightbox()
  },

  handleClick(event) {
    const deleteButton = event.target.closest("[data-delete-id]")
    if (deleteButton && this.el.contains(deleteButton)) {
      event.preventDefault()
      event.stopPropagation()

      if (window.confirm(deleteButton.dataset.confirmMessage || "Delete this image?")) {
        this.restoreScrollY = window.scrollY
        this.pushEvent("delete", {id: deleteButton.dataset.deleteId}, () => this.restoreScroll())
        window.setTimeout(() => { this.restoreScrollY = null }, 700)
      }
      return
    }

    const link = event.target.closest("a[data-lightbox-src]")
    if (!link || !this.el.contains(link)) return
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    if (performance.now() < this.suppressClickUntil) {
      event.preventDefault()
      return
    }

    event.preventDefault()
    const links = this.galleryLinks()
    this.openLightbox(Math.max(0, links.indexOf(link)))
  },

  handleTimeChange(event) {
    const input = event.target.closest("input[type='datetime-local'][data-image-id]")
    if (!input || !this.el.contains(input) || !input.value) return

    this.pushEvent("set_time", {
      "image-id": input.dataset.imageId,
      datetime: input.value,
    })
  },

  handleDragStart(event) {
    const figure = event.target.closest("[data-gallery-id]")
    if (!figure || !this.el.contains(figure)) return
    if (this.preventNativeDragUntil && performance.now() < this.preventNativeDragUntil) {
      event.preventDefault()
      return
    }

    this.beginReorder(figure)
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", figure.dataset.galleryId)
  },

  handleDragOver(event) {
    if (!this.dragged) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.placeDragged(event.clientX, event.clientY)
  },

  handleDrop(event) {
    if (!this.dragged) return
    event.preventDefault()
    this.finishReorder()
  },

  handlePointerDown(event) {
    if (event.target.closest("[data-no-drag]")) {
      this.preventNativeDragUntil = performance.now() + 700
      return
    }

    if (event.pointerType === "mouse") return

    const surface = event.target.closest("[data-gallery-drag-surface]")
    if (!surface || !this.el.contains(surface)) return

    const figure = surface.closest("[data-gallery-id]")
    const pointer = {
      id: event.pointerId,
      figure,
      startX: event.clientX,
      startY: event.clientY,
      lastY: event.clientY,
      started: false,
      scrolling: false,
    }
    pointer.timer = window.setTimeout(() => {
      if (this.pointerDrag !== pointer || pointer.scrolling) return
      pointer.started = true
      this.beginReorder(pointer.figure)
    }, TOUCH_DRAG_DELAY_MS)
    this.pointerDrag = pointer
    surface.setPointerCapture(event.pointerId)
  },

  handlePointerMove(event) {
    const pointer = this.pointerDrag
    if (!pointer || pointer.id !== event.pointerId) return

    if (!pointer.started) {
      const deltaX = event.clientX - pointer.startX
      const deltaY = event.clientY - pointer.startY
      const distance = Math.hypot(deltaX, deltaY)
      if (distance < DRAG_THRESHOLD) return

      window.clearTimeout(pointer.timer)
      if (Math.abs(deltaX) > Math.abs(deltaY)) {
        pointer.started = true
        this.beginReorder(pointer.figure)
      } else {
        pointer.scrolling = true
      }
    }

    if (pointer.scrolling) {
      event.preventDefault()
      window.scrollBy(0, pointer.lastY - event.clientY)
      pointer.lastY = event.clientY
      this.suppressClickUntil = performance.now() + 350
      return
    }

    event.preventDefault()
    this.placeDragged(event.clientX, event.clientY)

    const edge = 64
    if (event.clientY < edge) window.scrollBy(0, -14)
    if (event.clientY > window.innerHeight - edge) window.scrollBy(0, 14)
  },

  handlePointerUp(event) {
    const pointer = this.pointerDrag
    if (!pointer || pointer.id !== event.pointerId) return

    window.clearTimeout(pointer.timer)
    this.pointerDrag = null
    if (pointer.scrolling) {
      event.preventDefault()
      this.suppressClickUntil = performance.now() + 350
      return
    }

    if (pointer.started) {
      event.preventDefault()
      this.suppressClickUntil = performance.now() + 350
      this.finishReorder()
    }
  },

  beginReorder(figure) {
    if (this.dragged) return
    this.dragged = figure
    this.initialOrder = this.galleryIds()
    figure.classList.add("opacity-40", "scale-[0.98]")
    this.el.classList.add("select-none")
  },

  placeDragged(clientX, clientY) {
    const target = document.elementFromPoint(clientX, clientY)?.closest("[data-gallery-id]")
    if (!target || target === this.dragged || !this.el.contains(target)) return

    const rect = target.getBoundingClientRect()
    const nearSameRow = Math.abs(clientY - (rect.top + rect.height / 2)) < rect.height * 0.35
    const placeAfter = nearSameRow
      ? clientX > rect.left + rect.width / 2
      : clientY > rect.top + rect.height / 2

    this.el.insertBefore(this.dragged, placeAfter ? target.nextSibling : target)
  },

  finishReorder() {
    if (!this.dragged) return

    const movedId = this.dragged.dataset.galleryId
    this.dragged.classList.remove("opacity-40", "scale-[0.98]")
    this.el.classList.remove("select-none")
    const nextOrder = this.galleryIds()
    const changed = nextOrder.join("\n") !== this.initialOrder.join("\n")
    this.dragged = null

    if (changed) this.pushEvent("reorder", {id: movedId, ids: nextOrder})
  },

  galleryFigures() {
    return [...this.el.querySelectorAll(":scope > [data-gallery-id]")]
  },

  galleryIds() {
    return this.galleryFigures().map(figure => figure.dataset.galleryId)
  },

  galleryLinks() {
    return this.galleryFigures()
      .map(figure => figure.querySelector("a[data-lightbox-src]"))
      .filter(Boolean)
  },

  openLightbox(index) {
    if (!this.lightbox) return
    if (!this.lightbox.open) this.lightbox.showModal()
    document.body.style.overflow = "hidden"
    this.showLightboxImage(index)
  },

  showLightboxImage(index) {
    const links = this.galleryLinks()
    if (!links.length) return

    this.lightboxIndex = (index + links.length) % links.length
    const link = links[this.lightboxIndex]
    const src = link.dataset.lightboxSrc
    const expectedSrc = new URL(src, document.baseURI).href
    const alt = link.querySelector("img")?.alt || ""
    const date = link.dataset.lightboxDate || ""
    const token = ++this.lightboxLoadToken

    this.lightboxLoading.textContent = "loading image"
    this.lightboxLoading.classList.remove("hidden")
    this.lightboxImage.classList.add("hidden")
    this.lightboxImage.alt = alt
    this.lightboxOriginal.href = link.href
    this.lightboxCount.textContent = `${this.lightboxIndex + 1} / ${links.length}`
    this.lightboxCaption.textContent = alt
    this.lightboxDate.textContent = date

    this.lightboxImage.onload = () => {
      if (
        token !== this.lightboxLoadToken ||
        !this.lightbox.open ||
        this.lightboxImage.currentSrc !== expectedSrc
      ) return
      this.lightboxLoading.classList.add("hidden")
      this.lightboxImage.classList.remove("hidden")
    }
    this.lightboxImage.onerror = () => {
      if (token !== this.lightboxLoadToken || !this.lightbox.open) return
      this.lightboxLoading.textContent = "image could not be loaded"
    }
    this.lightboxImage.src = expectedSrc
    if (this.lightboxImage.complete && this.lightboxImage.naturalWidth > 0) {
      window.requestAnimationFrame(() => this.lightboxImage.onload?.())
    }
  },

  closeLightbox() {
    if (this.lightbox?.open) this.lightbox.close()
  },

  resetLightbox() {
    this.lightboxLoadToken += 1
    if (this.lightboxImage) {
      this.lightboxImage.onload = null
      this.lightboxImage.onerror = null
      this.lightboxImage.removeAttribute("src")
      this.lightboxImage.classList.add("hidden")
    }
    document.body.style.overflow = ""
  },

  handleLightboxClick(event) {
    if (event.target.closest("[data-lightbox-close]")) this.closeLightbox()
    if (event.target.closest("[data-lightbox-prev]")) this.showLightboxImage(this.lightboxIndex - 1)
    if (event.target.closest("[data-lightbox-next]")) this.showLightboxImage(this.lightboxIndex + 1)
    if (event.target === this.lightboxStage) this.closeLightbox()
  },

  handleKeydown(event) {
    if (!this.lightbox?.open) return
    if (event.key === "ArrowLeft") this.showLightboxImage(this.lightboxIndex - 1)
    if (event.key === "ArrowRight") this.showLightboxImage(this.lightboxIndex + 1)
  },

  handleTouchStart(event) {
    const touch = event.changedTouches[0]
    this.touchStart = {x: touch.clientX, y: touch.clientY}
  },

  handleTouchEnd(event) {
    if (!this.touchStart) return
    const touch = event.changedTouches[0]
    const deltaX = touch.clientX - this.touchStart.x
    const deltaY = touch.clientY - this.touchStart.y
    this.touchStart = null

    if (Math.abs(deltaX) < SWIPE_THRESHOLD || Math.abs(deltaX) <= Math.abs(deltaY)) return
    this.showLightboxImage(this.lightboxIndex + (deltaX < 0 ? 1 : -1))
  },

  restoreScroll() {
    if (this.restoreScrollY === null) return
    const top = this.restoreScrollY
    window.requestAnimationFrame(() => window.scrollTo({top, behavior: "auto"}))
    window.setTimeout(() => window.scrollTo({top, behavior: "auto"}), 60)
  },
}
