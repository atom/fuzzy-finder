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
      const editors = atom.workspace.getTextEditors().filter((editor) => editor.getPath())
      const activeEditor = atom.workspace.getActiveTextEditor()
      editors.sort((a, b) => {
        if (a === activeEditor) {
          return 1
        } else if (b === activeEditor) {
          return -1
        } else {
          return (b.lastOpened || 1) - (a.lastOpened || 1)
        }
      })

      const paths = Array.from(new Set(editors.map((editor) => editor.getPath())))
      await this.setItems(paths)
      if (paths.length > 0) {
        this.show()
      }
    }
  }
}
