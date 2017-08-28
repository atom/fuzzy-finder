/** @babel */

import {Disposable, CompositeDisposable} from 'atom'
import humanize from 'humanize-plus'

import FuzzyFinderView from './fuzzy-finder-view'
import PathLoader from './path-loader'

export default class ProjectView extends FuzzyFinderView {
  constructor (paths) {
    super()
    this.disposables = new CompositeDisposable()
    this.paths = paths
    this.reloadPaths = !this.paths || this.paths.length === 0
    this.reloadAfterFirstLoad = false

    const windowFocused = () => {
      if (this.paths) {
        this.reloadPaths = true
      } else {
        // The window gained focused while the first task was still running
        // so let it complete but reload the paths on the next populate call.
        this.reloadAfterFirstLoad = true
      }
    }
    window.addEventListener('focus', windowFocused)
    this.disposables.add(new Disposable(() => { window.removeEventListener('focus', windowFocused) }))

    this.disposables.add(atom.config.onDidChange('fuzzy-finder.ignoredNames', () => { this.reloadPaths = true }))
    this.disposables.add(atom.config.onDidChange('core.followSymlinks', () => { this.reloadPaths = true }))
    this.disposables.add(atom.config.onDidChange('core.ignoredNames', () => { this.reloadPaths = true }))
    this.disposables.add(atom.config.onDidChange('core.excludeVcsIgnoredPaths', () => { this.reloadPaths = true }))
    this.disposables.add(atom.project.onDidChangePaths(() => {
      this.reloadPaths = true
      this.paths = null
    }))
  }

  destroy () {
    if (this.loadPathsTask) {
      this.loadPathsTask.terminate()
    }

    this.disposables.dispose()
    return super.destroy()
  }

  async toggle () {
    if (this.panel && this.panel.isVisible()) {
      this.cancel()
    } else {
      this.show()
      await this.populate()
    }
  }

  async populate () {
    if (atom.project.getPaths().length === 0) {
      await this.setItems([])
      return
    }

    await this.setItems(this.paths || [])

    if (this.reloadPaths) {
      this.reloadPaths = false
      let task = null
      try {
        task = this.runLoadPathsTask(() => {
          if (this.reloadAfterFirstLoad) {
            this.reloadPaths = true
            this.reloadAfterFirstLoad = false
          }

          this.populate()
        })
      } catch (error) {
        // If, for example, a network drive is unmounted, @runLoadPathsTask will
        // throw ENOENT when it tries to get the realpath of all the project paths.
        // This catch block allows the file finder to still operate on the last
        // set of paths and still let the user know that something is wrong.
        if (error.code === 'ENOENT' || error.code === 'EPERM') {
          atom.notifications.addError('Project path not found!', {detail: error.message})
        } else {
          throw error
        }
      }

      if (this.paths) {
        await this.selectListView.update({loadingMessage: 'Reindexing project\u2026'})
      } else {
        await this.selectListView.update({loadingMessage: 'Indexing project\u2026', loadingBadge: '0'})
        if (task) {
          let pathsFound = 0
          task.on('load-paths:paths-found', (paths) => {
            pathsFound += paths.length
            this.selectListView.update({loadingMessage: 'Indexing project\u2026', loadingBadge: humanize.intComma(pathsFound)})
          })
        }
      }
    }
  }

  getEmptyMessage () {
    return 'Project is empty'
  }

  projectRelativePathsForFilePaths (filePaths) {
    const projectRelativePaths = super.projectRelativePathsForFilePaths(filePaths)
    const lastOpenedPath = this.getLastOpenedPath()
    if (lastOpenedPath) {
      for (let i = 0; i < projectRelativePaths.length; i++) {
        const {filePath} = projectRelativePaths[i]
        if (filePath === lastOpenedPath) {
          const [entry] = projectRelativePaths.splice(i, 1)
          projectRelativePaths.unshift(entry)
          break
        }
      }
    }

    return projectRelativePaths
  }

  getLastOpenedPath () {
    let activePath = null
    const activePaneItem = atom.workspace.getActivePaneItem()
    if (activePaneItem && activePaneItem.getPath) {
      activePath = activePaneItem.getPath()
    }

    let lastOpenedEditor = null
    for (const editor of atom.workspace.getTextEditors()) {
      const filePath = editor.getPath()
      if (!filePath) {
        continue
      }

      if (activePath === filePath) {
        continue
      }

      if (!lastOpenedEditor) {
        lastOpenedEditor = editor
      }

      if (editor.lastOpened > lastOpenedEditor.lastOpened) {
        lastOpenedEditor = editor
      }
    }

    return lastOpenedEditor ? lastOpenedEditor.getPath() : null
  }

  runLoadPathsTask (fn) {
    if (this.loadPathsTask) {
      this.loadPathsTask.terminate()
    }

    this.loadPathsTask = PathLoader.startTask((paths) => {
      this.paths = paths
      this.reloadPaths = false
      if (fn) {
        fn()
      }
    })
    return this.loadPathsTask
  }
}
