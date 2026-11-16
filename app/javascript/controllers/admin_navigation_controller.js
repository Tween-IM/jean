import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["dialog", "query", "item", "empty"]
  shortcut(event) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault(); this.open()
    }
  }
  open() { this.dialogTarget.showModal(); this.queryTarget.value = ""; this.filter(); this.queryTarget.focus() }
  close() { this.dialogTarget.close() }
  filter() {
    const query = this.queryTarget.value.trim().toLowerCase()
    let count = 0
    this.itemTargets.forEach(item => {
      item.hidden = !item.textContent.toLowerCase().includes(query)
      if (!item.hidden) count++
    })
    this.emptyTarget.hidden = count !== 0
  }
  enter(event) {
    if (event.key === "Enter") { event.preventDefault(); this.itemTargets.find(item => !item.hidden)?.click() }
  }
}
