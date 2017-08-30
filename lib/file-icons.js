const DefaultFileIcons = require('./default-file-icons')

class FileIcons {
  constructor () {
    this.service = new DefaultFileIcons()
  }

  getService () {
    return this.service
  }

  resetService () {
    this.service = new DefaultFileIcons()
  }

  setService (service) {
    this.service = service
  }
}

module.exports = new FileIcons()
