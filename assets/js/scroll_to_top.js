// Scrolls the window back to the top when the server pushes a "scroll-to-top"
// event, e.g. after paginating through course results.
export default {
  mounted() {
    this.handleEvent("scroll-to-top", () => {
      window.scrollTo({top: 0, behavior: "smooth"})
    })
  },
}
