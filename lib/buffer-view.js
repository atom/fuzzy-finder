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

      const workspacePaths = Array.from(new Set(workspaceEditors.map((editor) => editor.getPath())))
      let remotePaths = []
      if (this.teletype && this.teletype.getRemoteBuffers) {
        remotePaths = (await this.teletype.getRemoteBuffers()).map((b) => b.path)
      }
      const paths = workspacePaths.concat(remotePaths)
      if (paths.length > 0) {
        this.show()
        await this.setItems(paths)
      }
    }
  }
}
