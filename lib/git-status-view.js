/** @babel */

import fs from 'fs-plus'
import path from 'path'

import FuzzyFinderView from './fuzzy-finder-view-2'

export default class GitStatusView extends FuzzyFinderView {
  async toggle () {
    if (this.panel && this.panel.isVisible()) {
      this.cancel()
    } else if (atom.project.getRepositories().some((repo) => repo)) {
      const paths = []
      for (const repo of atom.project.getRepositories()) {
        if (repo) {
          const workingDirectory = repo.getWorkingDirectory()
          for (let filePath in repo.statuses) {
            filePath = path.join(workingDirectory, filePath)
            if (fs.isFileSync(filePath)) {
              paths.push(filePath)
            }
          }

        }
      }
      await this.setItems(paths)
      this.show()
    }
  }

  getEmptyMessage () {
    return 'Nothing to commit, working directory clean'
  }
}
