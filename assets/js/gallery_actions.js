export const GalleryActions = {
  mounted() {
    this.el.addEventListener("click", event => {
      const button = event.target.closest("[data-delete-id]")
      if (!button || !this.el.contains(button)) return

      event.preventDefault()
      event.stopPropagation()

      if (window.confirm(button.dataset.confirmMessage || "Delete this image?")) {
        this.pushEvent("delete", {id: button.dataset.deleteId})
      }
    })

    this.el.addEventListener("change", event => {
      const input = event.target.closest("input[type='datetime-local'][data-image-id]")
      if (!input || !this.el.contains(input) || !input.value) return

      this.pushEvent("set_time", {
        "image-id": input.dataset.imageId,
        datetime: input.value,
      })
    })
  }
}
