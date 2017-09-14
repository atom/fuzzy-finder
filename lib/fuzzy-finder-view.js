/** @babel */

import {Point, CompositeDisposable} from 'atom'
import fs from 'fs-plus'
import fuzzaldrin from 'fuzzaldrin'
import fuzzaldrinPlus from 'fuzzaldrin-plus'
import path from 'path'
import SelectListView from 'atom-select-list'

import {repositoryForPath} from './helpers'
import FileIcons from './file-icons'

export default class FuzzyFinderView {
  constructor () {
    this.previousQueryWasLineJump = false
    this.items = []
    this.selectListView = new SelectListView({
      items: this.items,
      maxResults: 10,
      emptyMessage: this.getEmptyMessage(),
      filterKeyForItem: (item) => item.projectRelativePath,
      filterQuery: (query) => {
        const colon = query.indexOf(':')
        if (colon !== -1) {
          query = query.slice(0, colon)
        }
        // Normalize to backslashes on Windows
        if (process.platform === 'win32') {
          query = query.replace(/\//g, '\\')
        }

        return query
      },
      didCancelSelection: () => { this.cancel() },
      didConfirmSelection: (item) => {
        this.confirm(item, {searchAllPanes: atom.config.get('fuzzy-finder.searchAllPanes')})
      },
      didConfirmEmptySelection: () => {
        this.confirm()
      },
      didChangeQuery: () => {
        const isLineJump = this.isQueryALineJump()
        if (!this.previousQueryWasLineJump && isLineJump) {
          this.previousQueryWasLineJump = true
          this.selectListView.update({
            items: [],
            emptyMessage: 'Jump to line in active editor'
          })
        } else if (this.previousQueryWasLineJump && !isLineJump) {
          this.previousQueryWasLineJump = false
          this.selectListView.update({
            items: this.items,
            emptyMessage: this.getEmptyMessage()
          })
        }
      },
      elementForItem: ({filePath, projectRelativePath}) => {
        const filterQuery = this.selectListView.getFilterQuery()
        const matches = this.useAlternateScoring
          ? fuzzaldrinPlus.match(projectRelativePath, filterQuery)
          : fuzzaldrin.match(projectRelativePath, filterQuery)

        const li = document.createElement('li')
        li.classList.add('two-lines')

        const repository = repositoryForPath(filePath)
        if (repository) {
          const status = repository.getCachedPathStatus(filePath)
          if (repository.isStatusNew(status)) {
            const div = document.createElement('div')
            div.classList.add('status', 'status-added', 'icon', 'icon-diff-added')
            li.appendChild(div)
          } else if (repository.isStatusModified(status)) {
            const div = document.createElement('div')
            div.classList.add('status', 'status-modified', 'icon', 'icon-diff-modified')
            li.appendChild(div)
          }
        }

        const iconClasses = FileIcons.getService().iconClassForPath(filePath, 'fuzzy-finder')
        let classList
        if (Array.isArray(iconClasses)) {
          classList = iconClasses
        } else if (iconClasses) {
          classList = iconClasses.toString().split(/\s+/g)
        } else {
          classList = []
        }

        const fileBasename = path.basename(filePath)
        const baseOffset = projectRelativePath.length - fileBasename.length
        const primaryLine = document.createElement('div')
        primaryLine.classList.add('primary-line', 'file', 'icon', ...classList)
        primaryLine.dataset.name = fileBasename
        primaryLine.dataset.path = projectRelativePath
        primaryLine.appendChild(highlight(fileBasename, matches, baseOffset))
        li.appendChild(primaryLine)

        const secondaryLine = document.createElement('div')
        secondaryLine.classList.add('secondary-line', 'path', 'no-icon')
        secondaryLine.appendChild(highlight(projectRelativePath, matches, 0))
        li.appendChild(secondaryLine)

        return li
      }
    })
    this.selectListView.element.classList.add('fuzzy-finder')

    const splitLeft = () => { this.splitOpenPath((pane) => pane.splitLeft.bind(pane)) }
    const splitRight = () => { this.splitOpenPath((pane) => pane.splitRight.bind(pane)) }
    const splitUp = () => { this.splitOpenPath((pane) => pane.splitUp.bind(pane)) }
    const splitDown = () => { this.splitOpenPath((pane) => pane.splitDown.bind(pane)) }
    atom.commands.add(this.selectListView.element, {
      'pane:split-left': splitLeft,
      'pane:split-left-and-copy-active-item': splitLeft,
      'pane:split-left-and-move-active-item': splitLeft,
      'pane:split-right': splitRight,
      'pane:split-right-and-copy-active-item': splitRight,
      'pane:split-right-and-move-active-item': splitRight,
      'pane:split-up': splitUp,
      'pane:split-up-and-copy-active-item': splitUp,
      'pane:split-up-and-move-active-item': splitUp,
      'pane:split-down': splitDown,
      'pane:split-down-and-copy-active-item': splitDown,
      'pane:split-down-and-move-active-item': splitDown,
      'fuzzy-finder:invert-confirm': () => {
        this.confirm(
          this.selectListView.getSelectedItem(),
          {searchAllPanes: !atom.config.get('fuzzy-finder.searchAllPanes')}
        )
      }
    })

    this.subscriptions = new CompositeDisposable()
    this.subscriptions.add(
      atom.config.observe('fuzzy-finder.useAlternateScoring', (newValue) => {
        this.useAlternateScoring = newValue
        if (this.useAlternateScoring) {
          this.selectListView.update({
            filter: (items, query) => {
              return query ? fuzzaldrinPlus.filter(items, query, {key: 'projectRelativePath'}) : items
            }
          })
        } else {
          this.selectListView.update({filter: null})
        }
      })
    )
  }

  get element () {
    return this.selectListView.element
  }

  destroy () {
    if (this.panel) {
      this.panel.destroy()
    }

    if (this.subscriptions) {
      this.subscriptions.dispose()
      this.subscriptions = null
    }

    return this.selectListView.destroy()
  }

  cancel () {
    if (atom.config.get('fuzzy-finder.preserveLastSearch')) {
      this.selectListView.refs.queryEditor.selectAll()
    } else {
      this.selectListView.reset()
    }

    this.hide()
  }

  confirm ({filePath} = {}, openOptions) {
    if (atom.workspace.getActiveTextEditor() && this.isQueryALineJump()) {
      const lineNumber = this.getLineNumber()
      this.cancel()
      this.moveToLine(lineNumber)
    } else if (!filePath) {
      this.cancel()
    } else if (fs.isDirectorySync(filePath)) {
      this.selectListView.update({errorMessage: 'Selected path is a directory'})
      setTimeout(() => { this.selectListView.update({errorMessage: null}) }, 2000)
    } else {
      const lineNumber = this.getLineNumber()
      this.cancel()
      this.openPath(filePath, lineNumber, openOptions)
    }
  }

  getEditorSelection () {
    const editor = atom.workspace.getActiveTextEditor()
    if (!editor) {
      return
    }
    const selectedText = editor.getSelectedText()
    if (/\n/m.test(selectedText)) {
      return
    }
    return selectedText
  }

  prefillQueryFromSelection () {
    const selectedText = this.getEditorSelection()
    if (selectedText) {
      this.selectListView.refs.queryEditor.setText(selectedText)
      const textLength = selectedText.length
      this.selectListView.refs.queryEditor.setSelectedBufferRange([[0, 0], [0, textLength]])
    }
  }

  show () {
    this.previouslyFocusedElement = document.activeElement
    if (!this.panel) {
      this.panel = atom.workspace.addModalPanel({item: this})
    }
    this.panel.show()
    if (atom.config.get('fuzzy-finder.prefillFromSelection') === true) {
      this.prefillQueryFromSelection()
    }
    this.selectListView.focus()
  }

  hide () {
    if (this.panel) {
      this.panel.hide()
    }

    if (this.previouslyFocusedElement) {
      this.previouslyFocusedElement.focus()
      this.previouslyFocusedElement = null
    }
  }

  async openPath (filePath, lineNumber, openOptions) {
    if (filePath) {
      await atom.workspace.open(filePath, openOptions)
      this.moveToLine(lineNumber)
    }
  }

  moveToLine (lineNumber = -1) {
    if (lineNumber < 0) {
      return
    }

    const editor = atom.workspace.getActiveTextEditor()
    if (editor) {
      const position = new Point(lineNumber, 0)
      editor.scrollToBufferPosition(position, {center: true})
      editor.setCursorBufferPosition(position)
      editor.moveToFirstCharacterOfLine()
    }
  }

  splitOpenPath (splitFn) {
    const {filePath} = this.selectListView.getSelectedItem() || {}
    const lineNumber = this.getLineNumber()
    const editor = atom.workspace.getActiveTextEditor()
    const activePane = atom.workspace.getActivePane()

    if (this.isQueryALineJump() && editor) {
      this.previouslyFocusedElement = null
      splitFn(activePane)({copyActiveItem: true})
      this.moveToLine(lineNumber)
    } else if (!filePath) {
      return // eslint-disable-line no-useless-return
    } else if (activePane) {
      this.previouslyFocusedElement = null
      splitFn(activePane)()
      this.openPath(filePath, lineNumber)
    } else {
      this.previouslyFocusedElement = null
      this.openPath(filePath, lineNumber)
    }
  }

  isQueryALineJump () {
    return (
      this.selectListView.getFilterQuery().trim() === '' &&
      this.selectListView.getQuery().indexOf(':') !== -1
    )
  }

  getLineNumber () {
    const query = this.selectListView.getQuery()
    const colon = query.indexOf(':')
    if (colon === -1) {
      return -1
    } else {
      return parseInt(query.slice(colon + 1)) - 1
    }
  }

  setItems (filePaths) {
    this.items = this.projectRelativePathsForFilePaths(filePaths)
    if (this.isQueryALineJump()) {
      return this.selectListView.update({items: [], loadingMessage: null, loadingBadge: null})
    } else {
      return this.selectListView.update({items: this.items, loadingMessage: null, loadingBadge: null})
    }
  }

  projectRelativePathsForFilePaths (filePaths) {
    // Don't regenerate project relative paths unless the file paths have changed
    if (filePaths !== this.filePaths) {
      const projectHasMultipleDirectories = atom.project.getDirectories().length > 1
      this.filePaths = filePaths
      this.projectRelativePaths = this.filePaths.map((filePath) => {
        let [rootPath, projectRelativePath] = atom.project.relativizePath(filePath)
        if (rootPath && projectHasMultipleDirectories) {
          projectRelativePath = path.join(path.basename(rootPath), projectRelativePath)
        }
        return {filePath, projectRelativePath}
      })
    }

    return this.projectRelativePaths
  }
}

function highlight (path, matches, offsetIndex) {
  let lastIndex = 0
  let matchedChars = []
  const fragment = document.createDocumentFragment()
  for (let matchIndex of matches) {
    matchIndex -= offsetIndex
    // If marking up the basename, omit path matches
    if (matchIndex < 0) {
      continue
    }
    const unmatched = path.substring(lastIndex, matchIndex)
    if (unmatched) {
      if (matchedChars.length > 0) {
        const span = document.createElement('span')
        span.classList.add('character-match')
        span.textContent = matchedChars.join('')
        fragment.appendChild(span)
        matchedChars = []
      }

      fragment.appendChild(document.createTextNode(unmatched))
    }

    matchedChars.push(path[matchIndex])
    lastIndex = matchIndex + 1
  }

  if (matchedChars.length > 0) {
    const span = document.createElement('span')
    span.classList.add('character-match')
    span.textContent = matchedChars.join('')
    fragment.appendChild(span)
  }

  // Remaining characters are plain text
  fragment.appendChild(document.createTextNode(path.substring(lastIndex)))
  return fragment
}
