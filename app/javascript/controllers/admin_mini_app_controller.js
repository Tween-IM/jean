import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["previewButton", "previewStatus"]
  static values = { previewUrl: String }

  disconnect() { this.previewRequest?.abort() }

  async fetchPreview() {
    const launch = this.element.elements.namedItem("manifest[entry_url]")
    const url = launch.value.trim()
    if (!url) {
      this.previewStatusTarget.textContent = "Enter a launch URL first."
      launch.focus()
      return
    }

    const request = new AbortController()
    this.previewRequest = request
    this.previewButtonTarget.disabled = true
    this.previewStatusTarget.textContent = "Reading website…"

    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        signal: request.signal,
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ url })
      })
      const preview = await response.json()
      if (launch.value.trim() !== url) {
        this.previewStatusTarget.textContent = "The launch URL changed. Fetch details for the new URL."
        return
      }
      if (!response.ok) {
        this.previewStatusTarget.textContent = preview.error || "Couldn’t fetch website details."
        return
      }

      const fields = {
        "mini_app[name]": preview.name,
        "mini_app[description]": preview.description,
        "manifest[icon_url]": preview.icon_url,
        "manifest[header_image]": preview.header_image,
        "manifest[screenshots]": preview.screenshots?.join("\n")
      }
      let filled = 0
      for (const [name, suggestion] of Object.entries(fields)) {
        const input = this.element.elements.namedItem(name)
        if (input && !input.value.trim() && suggestion) {
          input.value = suggestion
          filled++
        }
      }
      this.previewStatusTarget.textContent = filled
        ? `Filled ${filled} listing fields. Review them before saving.`
        : "No new details found for the blank fields."
    } catch (error) {
      if (error.name !== "AbortError") {
        this.previewStatusTarget.textContent = "Couldn’t fetch website details. You can still fill the listing manually."
      }
    } finally {
      if (!request.signal.aborted) this.previewButtonTarget.disabled = false
    }
  }

  connect() { this.refresh() }
  refresh() {
    const classification = this.element.querySelector('[name="mini_app[classification]"]')?.value
    const reserved = ["system:notifications", "wallet:admin", "messaging:broadcast", "analytics:detailed"]
    const limited = { community: ["public", "user:read", "storage:read", "storage:write"], beta: ["public", "storage:read", "storage:write"] }
    this.element.querySelectorAll('[name="manifest[permissions][]"][type=checkbox]').forEach(input => {
      const allowed = classification === "official" || (limited[classification] ? limited[classification].includes(input.value) : !reserved.includes(input.value) && !input.value.startsWith("privileged"))
      input.disabled = !allowed
      if (!allowed) input.checked = false
    })
  }
}
