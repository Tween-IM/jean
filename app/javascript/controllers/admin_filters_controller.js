import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (!HTMLElement.prototype.showPopover || this.element.dataset.filtersEnhanced) return
    const form = this.element
    this.fields = Array.from(form.querySelectorAll('input:not([type=hidden]):not([type=submit]), select, textarea')).filter(field => field.name)
    if (!this.fields.length) return
    form.dataset.filtersEnhanced = "true"
    this.originalClass = form.className
    this.labels = new Map(this.fields.map(field => [field, field.labels?.[0]?.textContent.trim() || field.parentElement.querySelector("label")?.textContent.trim() || field.name.replaceAll("_", " ")]))
    this.originalValues = new Map(this.fields.map(field => [field, field.type === "checkbox" ? field.checked : field.value]))
    const search = this.fields.find(field => field.name === "query" || field.type === "search")
    const sort = this.fields.find(field => field.name === "sort")
    const filters = this.fields.filter(field => field !== search && field !== sort)
    const hidden = Array.from(form.querySelectorAll('input[type=hidden]'))
    // Select controllers own their trigger and popup. Keep them adjacent when moving.
    this.fields.forEach(field => { const controller = this.application.getControllerForElementAndIdentifier(field, "admin-select"); if (controller) controller.disconnect() })
    form.replaceChildren(...hidden); form.className = "admin-data-toolbar"
    const main = document.createElement("div"); main.className = "admin-data-toolbar-main"
    if (search) {
      const wrap = document.createElement("div"); wrap.className = "admin-data-search"; wrap.innerHTML = this.icon("search")
      search.type = "search"; search.placeholder ||= "Search records…"; search.setAttribute("aria-label", this.labels.get(search) || "Search records")
      const submit = document.createElement("button"); submit.type = "submit"; submit.className = "admin-search-submit"; submit.textContent = "Search"
      wrap.append(search, submit); main.append(wrap)
    }
    if (filters.length) {
      this.trigger = document.createElement("button"); this.trigger.type = "button"; this.trigger.className = "admin-button admin-filter-trigger"; this.trigger.innerHTML = `${this.icon("filters")}<span>Filters</span>`
      this.panel = document.createElement("div"); this.panel.className = "admin-filter-panel"; this.panel.id = `filters-${crypto.randomUUID()}`; this.panel.setAttribute("popover", "auto"); this.panel.setAttribute("role", "dialog"); this.panel.setAttribute("aria-label", "Filter records")
      this.trigger.setAttribute("aria-controls", this.panel.id); this.trigger.setAttribute("aria-haspopup", "dialog"); this.trigger.setAttribute("aria-expanded", "false")
      const header = document.createElement("div"); header.className = "admin-filter-heading"; header.innerHTML = '<strong>Filter records</strong>'
      const close = document.createElement("button"); close.type = "button"; close.className = "admin-icon-button"; close.setAttribute("aria-label", "Close filters"); close.innerHTML = this.icon("close"); close.onclick = () => this.panel.hidePopover(); header.append(close)
      const body = document.createElement("div"); body.className = "admin-filter-fields"
      filters.forEach(field => body.append(this.field(field)))
      const footer = document.createElement("div"); footer.className = "admin-filter-footer"
      const reset = document.createElement("button"); reset.type = "button"; reset.className = "admin-button"; reset.textContent = "Reset filters"; reset.onclick = () => filters.forEach(field => { if (field.type === "checkbox") field.checked = false; else if (field.tagName === "SELECT") field.selectedIndex = 0; else field.value = ""; field.dispatchEvent(new Event("change", { bubbles: true })) })
      const apply = document.createElement("button"); apply.type = "submit"; apply.className = "admin-button admin-button-primary"; apply.textContent = "Apply filters"
      footer.append(reset, apply); this.panel.append(header, body, footer); main.append(this.trigger)
      this.trigger.onclick = () => {
        this.panel.showPopover(); const rect = this.trigger.getBoundingClientRect()
        this.panel.style.left = `${Math.max(12, Math.min(rect.right - 360, innerWidth - this.panel.offsetWidth - 12))}px`
        this.panel.style.top = `${Math.min(rect.bottom + 8, Math.max(12, innerHeight - this.panel.offsetHeight - 12))}px`
        this.trigger.setAttribute("aria-expanded", "true"); close.focus()
      }
      this.panel.addEventListener("toggle", event => { this.trigger.setAttribute("aria-expanded", String(event.newState === "open")); if (event.newState === "closed" && !this.submitting) filters.forEach(field => { const value = this.originalValues.get(field); if (field.type === "checkbox") field.checked = value; else field.value = value; field.dispatchEvent(new Event("change", { bubbles: true })) }) })
    }
    if (sort) { this.sort = sort; this.sortChange = () => form.requestSubmit(); sort.addEventListener("change", this.sortChange); const wrap = this.field(sort); wrap.classList.add("admin-data-sort"); main.append(wrap) }
    form.append(main); if (this.panel) form.append(this.panel)
    this.renderChips(filters)
    this.submit = () => { this.submitting = true; form.setAttribute("aria-busy", "true") }
    form.addEventListener("submit", this.submit)
    // Reconnect moved native selects only after their new field labels exist.
    this.fields.forEach(field => { const controller = this.application.getControllerForElementAndIdentifier(field, "admin-select"); if (controller) controller.connect() })
  }
  field(control) {
    const row = document.createElement("div"); row.className = "admin-filter-field"
    control.id ||= `field-${crypto.randomUUID()}`
    const label = document.createElement("label"); label.htmlFor = control.id; label.textContent = this.labels.get(control)
    if (control.type === "checkbox") { row.classList.add("admin-filter-checkbox"); label.prepend(control); row.append(label) }
    else row.append(label, control)
    return row
  }
  renderChips(filters) {
    const chips = document.createElement("div"); chips.className = "admin-filter-chips"
    let count = 0
    filters.forEach(field => {
      const value = this.originalValues.get(field)
      if (!value || (field.type !== "checkbox" && field.tagName === "SELECT" && field.options[0]?.value === value)) return
      count++
      const link = document.createElement("a"), url = new URL(location.href); url.searchParams.delete(field.name); url.searchParams.delete("page")
      link.href = url.pathname + url.search; link.className = "admin-filter-chip"
      const label = this.labels.get(field), selected = field.tagName === "SELECT" ? field.selectedOptions[0]?.textContent : value
      link.textContent = field.type === "checkbox" ? label : `${label}: ${selected}`; link.setAttribute("aria-label", `Remove ${label} filter`); link.insertAdjacentHTML("beforeend", this.icon("close")); chips.append(link)
    })
    if (count) {
      this.trigger?.insertAdjacentHTML("beforeend", `<span class="admin-filter-count">${count}</span>`)
      const clear = document.createElement("a"), url = new URL(location.href); filters.forEach(field => url.searchParams.delete(field.name)); url.searchParams.delete("page")
      clear.href = url.pathname + url.search; clear.textContent = "Clear all"; clear.className = "admin-clear-filters"; chips.append(clear); this.element.append(chips)
    }
  }
  icon(name) {
    const template = document.querySelector(`template[data-admin-control-icon="${name}"]`)
    return template?.innerHTML || ""
  }
  disconnect() { this.element.removeEventListener("submit", this.submit); this.sort?.removeEventListener("change", this.sortChange) }
}
