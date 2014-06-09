path = require 'path'
{$$, Point, SelectListView} = require 'atom'
fs = require 'fs-plus'
{match} = require 'fuzzaldrin'

module.exports =
class FuzzyFinderView extends SelectListView
  filePaths: null
  projectRelativePaths: null

  initialize: ->
    super

    @addClass('fuzzy-finder overlay from-top')
    @setMaxItems(10)

    @subscribe this, 'pane:split-left', =>
      @splitOpenPath (pane, session) -> pane.splitLeft(session)
    @subscribe this, 'pane:split-right', =>
      @splitOpenPath (pane, session) -> pane.splitRight(session)
    @subscribe this, 'pane:split-down', =>
      @splitOpenPath (pane, session) -> pane.splitDown(session)
    @subscribe this, 'pane:split-up', =>
      @splitOpenPath (pane, session) -> pane.splitUp(session)

  getFilterKey: ->
    'projectRelativePath'

  destroy: ->
    @cancel()
    @remove()

  viewForItem: ({filePath, projectRelativePath}) ->

    # Style matched characters in search results
    filterQuery = @getFilterQuery()
    matches = match(projectRelativePath, filterQuery)

    $$ ->

      highlighter = (path, matches, offsetIndex) =>
        lastIndex = 0
        for matchIndex in matches
          matchIndex -= offsetIndex
          continue if matchIndex < 0 # If marking up the basename, omit path matches
          unmatched = path.substring(lastIndex, matchIndex)
          matchedChar = path[matchIndex]

          @text unmatched if unmatched
          @strong matchedChar, class: 'matched-char'
          lastIndex = matchIndex + 1

        # Remaining characters are plain text
        @text path.substring(lastIndex)


      @li class: 'two-lines', =>
        repo = atom.project.getRepo()
        if repo?
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

        basename = path.basename(filePath)
        baseOffset = projectRelativePath.length - basename.length

        @div class: "primary-line file icon #{typeClass}", -> highlighter(basename, matches, baseOffset)
        @div class: 'secondary-line path no-icon', -> highlighter(projectRelativePath, matches, 0)

  openPath: (filePath, lineNumber) ->
    if filePath
      atom.workspaceView.open(filePath).done => @moveToLine(lineNumber)

  moveToLine: (lineNumber=-1) ->
    return unless lineNumber >= 0

    if editorView = atom.workspaceView.getActiveView()
      position = new Point(lineNumber)
      editorView.scrollToBufferPosition(position, center: true)
      editorView.editor.setCursorBufferPosition(position)
      editorView.editor.moveCursorToFirstCharacterOfLine()

  splitOpenPath: (fn) ->
    {filePath} = @getSelectedItem() ? {}
    return unless filePath

    lineNumber = @getLineNumber()
    if pane = atom.workspaceView.getActivePane()
      atom.project.open(filePath).done (editor) =>
        fn(pane, editor)
        @moveToLine(lineNumber)
    else
      @openPath(filePath, lineNumber)

  confirmed: ({filePath}) ->
    return unless filePath

    if fs.isDirectorySync(filePath)
      @setError('Selected path is a directory')
      setTimeout((=> @setError()), 2000)
    else
      lineNumber = @getLineNumber()
      @cancel()
      @openPath(filePath, lineNumber)

  getFilterQuery: ->
    query = super
    colon = query.indexOf(':')
    if colon is -1
      query
    else
      query[0...colon]

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
      @filePaths = filePaths
      @projectRelativePaths = @filePaths.map (filePath) ->
        projectRelativePath = atom.project.relativize(filePath)
        {filePath, projectRelativePath}

    @projectRelativePaths

  attach: ->
    @storeFocusedElement()
    atom.workspaceView.append(this)
    @focusFilterEditor()
