import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
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
