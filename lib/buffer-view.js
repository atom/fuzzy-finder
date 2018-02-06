/** @babel */

import FuzzyFinderView from './fuzzy-finder-view'

export default class BufferView extends FuzzyFinderView {
  getEmptyMessage () {
    return 'No open editors'
  }

  async toggle () {
    if (this.panel && this.panel.isVisible()) {
      this.cancel()
    } else {
      const workspaceEditors = atom.workspace.getTextEditors().filter((editor) => editor.getPath())
      const activeEditor = atom.workspace.getActiveTextEditor()
      workspaceEditors.sort((a, b) => {
        if (a === activeEditor) {
          return 1
        } else if (b === activeEditor) {
          return -1
        } else {
          return (b.lastOpened || 1) - (a.lastOpened || 1)
        }
      })

      const uniqueWorkspacePaths = Array.from(new Set(workspaceEditors.map((editor) => editor.getPath())))
      const workspaceItems = this.projectRelativePathsForFilePaths(uniqueWorkspacePaths)

      let remoteItems
      if (this.teletype) {
        const remoteBuffers = await this.teletype.getRemoteBuffers()
        remoteItems = remoteBuffers.map((b) => {
          return {filePath: b.uri, label: b.label}
        })
      } else {
        remoteItems = []
      }

      const items = remoteItems.concat(workspaceItems)
      if (items.length > 0) {
        this.show()
        await this.setItems(items)
      }
    }
  }
}
