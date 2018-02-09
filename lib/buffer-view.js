const FuzzyFinderView = require('./fuzzy-finder-view')
const path = require('path')

module.exports =
class BufferView extends FuzzyFinderView {
  setTeletypeService (teletypeService) {
    this.teletypeService = teletypeService
  }

  getEmptyMessage () {
    return 'No open editors'
  }

  async toggle () {
    if (this.panel && this.panel.isVisible()) {
      this.cancel()
    } else {
      const itemsByURI = new Map()
      await this.addRemoteEditors(itemsByURI)
      this.addLocalEditors(itemsByURI)

      const items = this.sortItems(itemsByURI)
      if (items.length > 0) {
        this.show()
        await this.setItems(items)
      }
    }
  }

  async addRemoteEditors (itemsByURI) {
    const remoteEditors = this.teletypeService ? await this.teletypeService.getRemoteEditors() : []
    for (let i = 0; i < remoteEditors.length; i++) {
      const remoteEditor = remoteEditors[i]
      const item = {
        uri: remoteEditor.uri,
        filePath: remoteEditor.path,
        label: remoteEditor.label,
        lastOpened: undefined
      }
      itemsByURI.set(remoteEditor.uri, item)
    }
  }

  addLocalEditors (itemsByURI) {
    const projectHasMultipleDirectories = atom.project.getDirectories().length > 1
    const localEditors = atom.workspace.getTextEditors()
    for (let i = 0; i < localEditors.length; i++) {
      const localEditor = localEditors[i]
      const localEditorURI = localEditor.getURI()
      if (!localEditorURI) continue

      let item = itemsByURI.get(localEditorURI)
      if (item) {
        item.lastOpened = localEditor.lastOpened
      } else {
        const localEditorPath = localEditor.getPath()
        const [projectRootPath, projectRelativePath] = atom.project.relativizePath(localEditorPath)
        const label =
          projectRootPath && projectHasMultipleDirectories
            ? path.join(path.basename(projectRootPath), projectRelativePath)
            : projectRelativePath
        item = {
          uri: localEditorURI,
          filePath: localEditorPath,
          label,
          lastOpened: localEditor.lastOpened
        }
        itemsByURI.set(localEditorURI, item)
      }
    }
  }

  sortItems (itemsByURI) {
    const activeEditor = atom.workspace.getActiveTextEditor()
    const activeEditorURI = activeEditor ? activeEditor.getURI() : null
    const items = Array.from(itemsByURI.values())
    items.sort((a, b) => {
      if (a.uri === activeEditorURI) {
        return 1
      } else if (b.uri === activeEditorURI) {
        return -1
      } else {
        return (b.lastOpened || 1) - (a.lastOpened || 1)
      }
    })
    return items
  }
}
