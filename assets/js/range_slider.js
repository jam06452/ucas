// Client-side behaviour for the dual-handle range sliders (UCAS tariff and
// course duration).
//
// Two native range inputs are stacked over a shared track. Dragging is handled
// entirely here so the handles track the pointer at 60fps with no server round
// trips; the LiveView is only notified once, when the user releases a handle.
// The server event and input names are read from data attributes, so the same
// hook backs every range slider on the page.
export default {
  mounted() {
    this.minInput = this.el.querySelector('input[data-role="min"]')
    this.maxInput = this.el.querySelector('input[data-role="max"]')
    this.fill = this.el.querySelector('[data-role="fill"]')
    this.label = this.el.querySelector('[data-role="range-label"]')

    this.event = this.el.dataset.event
    this.boundsMin = parseFloat(this.el.dataset.boundsMin)
    this.boundsMax = parseFloat(this.el.dataset.boundsMax)
    // Display-only: raw values are scaled and formatted for the label, e.g.
    // tariff points (scale 1) or months rendered as years (scale 12).
    this.scale = parseFloat(this.el.dataset.scale || "1")
    this.decimals = parseInt(this.el.dataset.decimals || "0", 10)
    this.unit = this.el.dataset.unit || ""

    this.onInput = () => this.render()
    this.onChange = () => {
      this.render()
      this.pushEvent(this.event, {
        [this.minInput.name]: this.minInput.value,
        [this.maxInput.name]: this.maxInput.value,
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
    let min = parseFloat(this.minInput.value)
    let max = parseFloat(this.maxInput.value)

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
      this.label.textContent = `${this.format(min)} - ${this.format(max)}${plus} ${this.unit}`
    }
  },

  format(value) {
    return (value / this.scale).toFixed(this.decimals).replace(/\.0$/, "")
  },
}
