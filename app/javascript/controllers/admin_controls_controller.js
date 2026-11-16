import { Controller } from "@hotwired/stimulus"

// Adapts Rails form controls, including newly loaded drawers, to one component system.
export default class extends Controller {
  connect() {
    this.upgrade()
    this.observer = new MutationObserver(() => this.upgrade())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }
  upgrade() {
    this.element.querySelectorAll("select:not([multiple])").forEach(select => {
      if (!select.dataset.controller?.includes("admin-select")) select.dataset.controller = `${select.dataset.controller || ""} admin-select`.trim()
    })
    this.element.querySelectorAll('form[method="get"]').forEach(form => {
      if (form.dataset.adminToolbar === "false" || form.closest(".admin-topbar") || form.dataset.controller?.includes("admin-filters")) return
      form.dataset.controller = `${form.dataset.controller || ""} admin-filters`.trim()
    })
  }
  submit(event) { event.target.form?.requestSubmit() }
  disconnect() { this.observer?.disconnect() }
}
