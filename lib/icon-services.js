const DefaultFileIcons = require('./default-file-icons')
const {Emitter} = require('atom')

const defaultServices = {
  'file-icons': new DefaultFileIcons(),
  'element-icons': null
}

class IconServices {
  constructor () {
    this.emitter = new Emitter()
    this.activeServices = Object.assign({}, defaultServices)
  }

  get (name) {
    return this.activeServices[name] || defaultServices[name]
  }

  reset (name) {
    this.set(name, defaultServices[name])
  }

  set (name, service) {
    if (service !== this.activeServices[name]) {
      this.activeServices[name] = service
      this.emitter.emit('did-change')
    }
  }

  onDidChange (callback) {
    return this.emitter.on('did-change', callback)
  }
}

module.exports = new IconServices()
