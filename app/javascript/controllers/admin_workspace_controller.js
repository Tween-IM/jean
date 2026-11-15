import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "frame", "fullPage", "loading", "confirmation", "message", "cancelButton", "confirmButton", "toast"]

  connect() {
    if (!this.hasDrawerTarget) return
    this.previousConfirm = window.Turbo?.config?.forms?.confirm
    if (window.Turbo?.config?.forms) window.Turbo.config.forms.confirm = (message) => this.confirm(message)
    this.beforeCache = () => { this.drawerTarget.close(); this.confirmationTarget.close() }
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    if (!this.hasDrawerTarget) return
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    if (window.Turbo?.config?.forms) window.Turbo.config.forms.confirm = this.previousConfirm
    this.resolveConfirmation?.(false)
    clearTimeout(this.toastTimer)
  }

  open(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    this.trigger = event.currentTarget
    this.fullPageTarget.href = event.currentTarget.href
    this.frameTarget.innerHTML = ""
    this.loadingTarget.hidden = false
    if (!this.drawerTarget.open) this.drawerTarget.showModal()
  }

  loaded(event) {
    if (event.target !== this.frameTarget) return
    this.loadingTarget.hidden = true
    if (!this.drawerTarget.open) this.drawerTarget.showModal()
    const heading = this.frameTarget.querySelector("h1, h2")
    if (heading) { heading.tabIndex = -1; heading.focus({ preventScroll: true }) }
    this.frameTarget.querySelector(".admin-detail-body")?.scrollTo(0, 0)
  }

  missing(event) {
    if (event.target !== this.frameTarget) return
    event.preventDefault()
    this.loadingTarget.hidden = true
    this.frameTarget.textContent = "This page could not be loaded here. Open the full page to continue."
  }

  close() {
    this.drawerTarget.close()
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = ""
    this.trigger?.focus()
  }
  cancelDrawer(event) { event.preventDefault(); this.close() }
  backdrop(event) { if (event.target === this.drawerTarget) this.close() }

  confirm(message) {
    this.messageTarget.textContent = message
    this.confirmationTarget.showModal()
    this.cancelButtonTarget.focus()
    return new Promise(resolve => {
      const finish = (answer) => {
        this.confirmationTarget.close()
        this.confirmButtonTarget.onclick = null
        this.cancelButtonTarget.onclick = null
        this.confirmationTarget.oncancel = null
        this.resolveConfirmation = null
        resolve(answer)
      }
      this.resolveConfirmation = finish
      this.confirmButtonTarget.onclick = () => finish(true)
      this.cancelButtonTarget.onclick = () => finish(false)
      this.confirmationTarget.oncancel = (event) => { event.preventDefault(); finish(false) }
    })
  }

  async copy(event) {
    try {
      await navigator.clipboard.writeText(event.currentTarget.dataset.copyValue)
      this.toastTarget.textContent = "Copied to clipboard"
    } catch { this.toastTarget.textContent = "Copy unavailable. Select and copy the reference manually." }
    this.toastTarget.hidden = false
    clearTimeout(this.toastTimer)
    this.toastTimer = setTimeout(() => { this.toastTarget.hidden = true }, 2500)
  }
}
