import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["toggle"]
  toggle() {
    const open = this.element.classList.toggle("menu-open")
    this.toggleTargets.forEach(button => button.setAttribute("aria-expanded", String(open)))
  }
}
