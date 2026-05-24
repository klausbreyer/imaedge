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
  }
}
