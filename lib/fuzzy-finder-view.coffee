path = require 'path'
{Point} = require 'atom'
{$$, SelectListView} = require 'atom-space-pen-views'
{repositoryForPath} = require './helpers'
fs = require 'fs-plus'
{match} = require 'fuzzaldrin'

module.exports =
class FuzzyFinderView extends SelectListView
  filePaths: null
  projectRelativePaths: null

  initialize: ->
    super

    @addClass('fuzzy-finder')
    @setMaxItems(10)

    atom.commands.add @element,
      'pane:split-left': =>
        @splitOpenPath (pane, item) -> pane.splitLeft(items: [item])
      'pane:split-right': =>
        @splitOpenPath (pane, item) -> pane.splitRight(items: [item])
      'pane:split-down': =>
        @splitOpenPath (pane, item) -> pane.splitDown(items: [item])
      'pane:split-up': =>
        @splitOpenPath (pane, item) -> pane.splitUp(items: [item])
      'fuzzy-finder:invert-confirm': =>
        @confirmInvertedSelection()

    atom.commands.add '.fuzzy-finder',
      'core:move-down': =>
        @previewSelection()
      'core:move-up': =>
        @previewSelection()

  getFilterKey: ->
    'projectRelativePath'

  cancel: ->
    if atom.config.get('fuzzy-finder.preserveLastSearch')
      lastSearch = @getFilterQuery()
      super

      @filterEditorView.setText(lastSearch)
      @filterEditorView.getModel().selectAll()
    else
      super

  destroy: ->
    @cancel()
    @panel?.destroy()

  viewForItem: ({filePath, projectRelativePath}) ->

    # Style matched characters in search results
    filterQuery = @getFilterQuery()
    matches = match(projectRelativePath, filterQuery)

    $$ ->

      highlighter = (path, matches, offsetIndex) =>
        lastIndex = 0
        matchedChars = [] # Build up a set of matched chars to be more semantic

        for matchIndex in matches
          matchIndex -= offsetIndex
          continue if matchIndex < 0 # If marking up the basename, omit path matches
          unmatched = path.substring(lastIndex, matchIndex)
          if unmatched
            @span matchedChars.join(''), class: 'character-match' if matchedChars.length
            matchedChars = []
            @text unmatched
          matchedChars.push(path[matchIndex])
          lastIndex = matchIndex + 1

        @span matchedChars.join(''), class: 'character-match' if matchedChars.length

        # Remaining characters are plain text
        @text path.substring(lastIndex)


      @li class: 'two-lines', =>
        if (repo = repositoryForPath(filePath))?
          status = repo.getCachedPathStatus(filePath)
          if repo.isStatusNew(status)
            @div class: 'status status-added icon icon-diff-added'
          else if repo.isStatusModified(status)
            @div class: 'status status-modified icon icon-diff-modified'

        ext = path.extname(filePath)
        if fs.isReadmePath(filePath)
          typeClass = 'icon-book'
        else if fs.isCompressedExtension(ext)
          typeClass = 'icon-file-zip'
        else if fs.isImageExtension(ext)
          typeClass = 'icon-file-media'
        else if fs.isPdfExtension(ext)
          typeClass = 'icon-file-pdf'
        else if fs.isBinaryExtension(ext)
          typeClass = 'icon-file-binary'
        else
          typeClass = 'icon-file-text'

        fileBasename = path.basename(filePath)
        baseOffset = projectRelativePath.length - fileBasename.length

        @div class: "primary-line file icon #{typeClass}", 'data-name': fileBasename, 'data-path': projectRelativePath, -> highlighter(fileBasename, matches, baseOffset)
        @div class: 'secondary-line path no-icon', -> highlighter(projectRelativePath, matches, 0)

  openPath: (filePath, lineNumber, openOptions, preview=false) ->
    if filePath
      if preview
        atom.workspace.open(filePath, openOptions).done => @moveToLine(lineNumber)
      else
        atom.workspace.open(filePath, openOptions).done (editor) =>
          editorElement = atom.views.getView(editor)
          atom.commands.dispatch(editorElement, 'tabs:keep-preview-tab')
          @moveToLine(lineNumber)

  moveToLine: (lineNumber=-1) ->
    return unless lineNumber >= 0

    if textEditor = atom.workspace.getActiveTextEditor()
      position = new Point(lineNumber)
      textEditor.scrollToBufferPosition(position, center: true)
      textEditor.setCursorBufferPosition(position)
      textEditor.moveToFirstCharacterOfLine()

  splitOpenPath: (fn) ->
    {filePath} = @getSelectedItem() ? {}

    if @isQueryALineJump() and editor = atom.workspace.getActiveTextEditor()
      lineNumber = @getLineNumber()
      pane = atom.workspace.getActivePane()
      fn(pane, pane.copyActiveItem())
      @moveToLine(lineNumber)
    else if not filePath
      return
    else if pane = atom.workspace.getActivePane()
      atom.project.open(filePath).done (editor) =>
        fn(pane, editor)
        @moveToLine(lineNumber)
    else
      @openPath(filePath, lineNumber)

  populateList: ->
    if @isQueryALineJump()
      @list.empty()
      @setError('Jump to line in active editor')
    else
      super

  previewSelection: ->
    if atom.config.get('fuzzy-finder.previewSelection')
      {filePath} = @getSelectedItem() ? {}
      if filePath
        lineNumber = @getLineNumber()
        @openPath(filePath, lineNumber, {searchAllPanes: atom.config.get('fuzzy-finder.searchAllPanes'), activatePane: false}, true)

  confirmSelection: ->
    item = @getSelectedItem()
    @confirmed(item, searchAllPanes: atom.config.get('fuzzy-finder.searchAllPanes'))

  confirmInvertedSelection: ->
    item = @getSelectedItem()
    @confirmed(item, searchAllPanes: not atom.config.get('fuzzy-finder.searchAllPanes'))

  confirmed: ({filePath}={}, openOptions) ->
    if atom.workspace.getActiveTextEditor() and @isQueryALineJump()
      lineNumber = @getLineNumber()
      @cancel()
      @moveToLine(lineNumber)
    else if not filePath
      @cancel()
    else if fs.isDirectorySync(filePath)
      @setError('Selected path is a directory')
      setTimeout((=> @setError()), 2000)
    else
      lineNumber = @getLineNumber()
      @cancel()
      @openPath(filePath, lineNumber, openOptions)

  isQueryALineJump: ->
    query = @filterEditorView.getModel().getText()
    colon = query.indexOf(':')
    trimmedPath = @getFilterQuery().trim()

    trimmedPath is '' and colon isnt -1

  getFilterQuery: ->
    query = super
    colon = query.indexOf(':')
    query = query[0...colon] if colon isnt -1
    # Normalize to backslashes on Windows
    query = query.replace(/\//g, '\\') if process.platform is 'win32'
    query

  getLineNumber: ->
    query = @filterEditorView.getText()
    colon = query.indexOf(':')
    if colon is -1
      -1
    else
      parseInt(query[colon+1..]) - 1

  setItems: (filePaths) ->
    super(@projectRelativePathsForFilePaths(filePaths))

  projectRelativePathsForFilePaths: (filePaths) ->
    # Don't regenerate project relative paths unless the file paths have changed
    if filePaths isnt @filePaths
      projectHasMultipleDirectories = atom.project.getDirectories().length > 1

      @filePaths = filePaths
      @projectRelativePaths = @filePaths.map (filePath) ->
        [rootPath, projectRelativePath] = atom.project.relativizePath(filePath)
        if rootPath and projectHasMultipleDirectories
          projectRelativePath = path.join(path.basename(rootPath), projectRelativePath)
        {filePath, projectRelativePath}

    @projectRelativePaths

  show: ->
    @storeFocusedElement()
    @panel ?= atom.workspace.addModalPanel(item: this)
    @panel.show()
    @focusFilterEditor()

  hide: ->
    @panel?.hide()

  cancelled: ->
    @hide()
