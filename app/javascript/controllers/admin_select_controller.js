import { Controller } from "@hotwired/stimulus"

// Progressive enhancement: the native select remains the submitted source of truth.
export default class extends Controller {
  connect() {
    this.select = this.element
    if (this.select.multiple || !HTMLElement.prototype.showPopover || this.select.dataset.enhanced) return
    this.select.dataset.enhanced = "true"
    this.originalTabIndex = this.select.getAttribute("tabindex")
    this.label = this.select.labels?.[0]
    this.labelText = this.label?.textContent.trim() || this.select.getAttribute("aria-label") || this.select.name.replaceAll("_", " ")
    this.id = `select-${crypto.randomUUID()}`
    this.button = document.createElement("button")
    this.button.type = "button"; this.button.id = `${this.id}-trigger`; this.button.className = "admin-select-trigger"
    this.button.setAttribute("aria-haspopup", "dialog"); this.button.setAttribute("aria-expanded", "false")
    this.button.setAttribute("aria-controls", this.id)
    this.menu = document.createElement("div"); this.menu.id = this.id; this.menu.className = "admin-select-menu"
    this.menu.setAttribute("popover", "auto"); this.menu.setAttribute("role", "dialog"); this.menu.setAttribute("aria-label", `Choose ${this.labelText}`)
    this.search = document.createElement("input"); this.search.type = "text"; this.search.className = "admin-select-search"
    this.search.placeholder = "Search options…"; this.search.setAttribute("role", "combobox"); this.search.setAttribute("aria-label", `Search ${this.labelText}`)
    this.search.setAttribute("aria-autocomplete", "list"); this.search.setAttribute("aria-expanded", "true"); this.search.setAttribute("aria-controls", `${this.id}-options`)
    this.list = document.createElement("div"); this.list.id = `${this.id}-options`; this.list.className = "admin-select-options"
    this.list.setAttribute("role", "listbox"); this.list.setAttribute("aria-label", this.labelText)
    this.menu.append(this.search, this.list); this.select.after(this.button, this.menu)
    this.select.classList.add("admin-native-select"); this.select.setAttribute("aria-hidden", "true"); this.select.tabIndex = -1
    if (this.label) this.label.htmlFor = this.button.id
    this.button.onclick = () => this.open()
    this.button.onkeydown = event => { if (["ArrowDown", "ArrowUp"].includes(event.key)) { event.preventDefault(); this.open() } }
    this.search.oninput = () => this.render()
    this.menu.onkeydown = event => this.keydown(event)
    this.menu.addEventListener("toggle", () => { this.button.setAttribute("aria-expanded", String(this.menu.matches(":popover-open"))) })
    this.change = () => this.sync()
    this.select.addEventListener("change", this.change)
    this.invalid = event => { event.preventDefault(); this.button.setAttribute("aria-invalid", "true"); this.button.focus(); this.button.title = this.select.validationMessage }
    this.select.addEventListener("invalid", this.invalid)
    this.reset = () => setTimeout(() => this.sync(), 0)
    this.select.form?.addEventListener("reset", this.reset)
    this.optionsObserver = new MutationObserver(() => this.sync())
    this.optionsObserver.observe(this.select, { childList: true, subtree: true, attributes: true, attributeFilter: ['disabled', 'aria-invalid'] })
    this.sync()
  }
  sync() {
    if (!this.button) return
    const current = this.select.selectedOptions[0]
    this.button.textContent = current?.textContent || "Select…"
    this.button.setAttribute("aria-label", `${this.labelText}: ${current?.textContent || "Select"}`)
    this.button.disabled = this.select.disabled
    if (this.select.getAttribute('aria-invalid') === 'true') this.button.setAttribute('aria-invalid', 'true')
    else this.button.removeAttribute('aria-invalid')
    if (this.select.getAttribute('aria-describedby')) this.button.setAttribute('aria-describedby', this.select.getAttribute('aria-describedby'))
  }
  open() {
    if (this.menu.matches(":popover-open")) return this.close()
    this.search.value = ""; this.render(); this.menu.showPopover()
    const rect = this.button.getBoundingClientRect(), height = Math.min(320, window.innerHeight - 32)
    this.menu.style.width = `${Math.min(Math.max(rect.width, 240), window.innerWidth - 24)}px`
    this.menu.style.left = `${Math.max(12, Math.min(rect.left, window.innerWidth - this.menu.offsetWidth - 12))}px`
    this.menu.style.top = `${rect.bottom + height > window.innerHeight && rect.top > height ? rect.top - this.menu.offsetHeight - 6 : rect.bottom + 6}px`
    this.button.setAttribute("aria-expanded", "true"); this.search.focus()
  }
  render() {
    const query = this.search.value.trim().toLocaleLowerCase()
    this.options = Array.from(this.select.options).filter(option => !option.hidden && !option.disabled && !option.parentElement.disabled && option.text.toLocaleLowerCase().includes(query))
    this.list.replaceChildren()
    this.options.forEach((option, index) => {
      const item = document.createElement("div"); item.id = `${this.id}-${index}`; item.className = "admin-select-option"; item.setAttribute("role", "option")
      item.setAttribute("aria-selected", String(option.selected)); item.textContent = option.text
      item.onpointerdown = event => event.preventDefault()
      item.onclick = () => this.choose(index)
      this.list.append(item)
    })
    if (!this.options.length) { const empty = document.createElement("p"); empty.className = "admin-select-empty"; empty.textContent = "No matching options"; this.list.append(empty) }
    this.active = Math.max(0, this.options.findIndex(option => option.selected)); this.highlight()
  }
  keydown(event) {
    if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); this.close() }
    if (event.key === "Tab") { this.menu.hidePopover(); return }
    if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
      event.preventDefault()
      this.active = event.key === "Home" ? 0 : event.key === "End" ? this.options.length - 1 : Math.max(0, Math.min(this.options.length - 1, this.active + (event.key === "ArrowDown" ? 1 : -1)))
      this.highlight()
    }
    if (event.key === "Enter") { event.preventDefault(); this.choose(this.active) }
  }
  highlight() {
    this.list.querySelectorAll("[role=option]").forEach((item, index) => item.classList.toggle("is-focused", index === this.active))
    const active = this.list.querySelectorAll("[role=option]")[this.active]
    if (active) { this.search.setAttribute("aria-activedescendant", active.id); active.scrollIntoView({ block: "nearest" }) }
    else this.search.removeAttribute("aria-activedescendant")
  }
  choose(index) {
    if (!this.options[index]) return
    this.select.value = this.options[index].value
    this.select.dispatchEvent(new Event("change", { bubbles: true }))
    this.close()
  }
  close() { this.menu.hidePopover(); this.button.focus() }
  disconnect() {
    if (!this.button) return
    this.optionsObserver?.disconnect()
    this.select.removeEventListener("change", this.change); this.select.removeEventListener("invalid", this.invalid)
    this.select.form?.removeEventListener("reset", this.reset)
    this.button.remove(); this.menu.remove(); delete this.select.dataset.enhanced
    this.select.classList.remove("admin-native-select"); this.select.removeAttribute("aria-hidden")
    if (this.originalTabIndex === null) this.select.removeAttribute("tabindex"); else this.select.setAttribute("tabindex", this.originalTabIndex)
    if (this.label) this.label.htmlFor = this.select.id
  }
}
