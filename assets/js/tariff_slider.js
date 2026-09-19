// Client-side behaviour for the UCAS tariff range slider.
//
// Two native range inputs are stacked over a shared track. Dragging is handled
// entirely here so the handles track the pointer at 60fps with no server round
// trips; the LiveView is only notified once, when the user releases a handle.
// The server's `handle_event("tariff", ...)` expects `tariff_min`/`tariff_max`.
export default {
  mounted() {
    this.minInput = this.el.querySelector('input[name="tariff_min"]')
    this.maxInput = this.el.querySelector('input[name="tariff_max"]')
    this.fill = this.el.querySelector('[data-role="fill"]')
    this.label = this.el.parentElement.querySelector('[data-role="tariff-label"]')

    this.boundsMin = parseInt(this.el.dataset.boundsMin, 10)
    this.boundsMax = parseInt(this.el.dataset.boundsMax, 10)

    this.onInput = () => this.render()
    this.onChange = () => {
      this.render()
      this.pushEvent("tariff", {
        tariff_min: this.minInput.value,
        tariff_max: this.maxInput.value,
      })
    }

    this.minInput.addEventListener("input", this.onInput)
    this.maxInput.addEventListener("input", this.onInput)
    this.minInput.addEventListener("change", this.onChange)
    this.maxInput.addEventListener("change", this.onChange)

    this.render()
  },

  updated() {
    // The server may re-render with new values (e.g. "Clear" or back/forward
    // navigation); reflect them without fighting an in-progress drag.
    this.render()
  },

  destroyed() {
    this.minInput.removeEventListener("input", this.onInput)
    this.maxInput.removeEventListener("input", this.onInput)
    this.minInput.removeEventListener("change", this.onChange)
    this.maxInput.removeEventListener("change", this.onChange)
  },

  render() {
    let min = parseInt(this.minInput.value, 10)
    let max = parseInt(this.maxInput.value, 10)

    // Keep the handles from crossing; the server normalizes the same way.
    if (min > max) {
      if (document.activeElement === this.minInput) {
        max = min
        this.maxInput.value = max
      } else {
        min = max
        this.minInput.value = min
      }
    }

    const span = this.boundsMax - this.boundsMin || 1
    const left = ((min - this.boundsMin) / span) * 100
    const width = ((max - min) / span) * 100

    this.fill.style.left = `${left}%`
    this.fill.style.width = `${width}%`

    // Keep the lower handle grabbable when both handles meet.
    this.minInput.classList.toggle("z-20", min >= max)
    this.minInput.classList.toggle("z-10", min < max)

    if (this.label) {
      const plus = max >= this.boundsMax ? "+" : ""
      this.label.textContent = `${min} - ${max}${plus} Points`
    }
  },
}
