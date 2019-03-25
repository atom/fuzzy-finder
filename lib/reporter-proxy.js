module.exports = class ReporterProxy {
  constructor () {
    this.reporter = null
    this.queue = []

    this.eventType = 'fuzzy-finder-v1'
  }

  setReporter (reporter) {
    this.reporter = reporter
    let customEvent
    while ((customEvent = this.queue.shift())) {
      this.reporter.addCustomEvent(customEvent.category, customEvent)
    }
  }

  unsetReporter () {
    delete this.reporter
  }

  sendCrawlEvent (duration, numFiles, crawlerType) {
    const metadata = {
      ec: 'time-to-crawl',
      el: crawlerType,
      ev: numFiles
    }

    if (this.reporter) {
      this.reporter.addTiming(this.eventType, duration, metadata)
    } else {
      this.queue.push([event])
    }
  }
}
