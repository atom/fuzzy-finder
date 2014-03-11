path = require 'path'
{$$, Point, SelectListView} = require 'atom'
fs = require 'fs-plus'

module.exports =
class FuzzyFinderView extends SelectListView
  allowActiveEditorChange: false
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
    $$ ->
      @li class: 'two-lines', =>
        repo = atom.project.getRepo()
        if repo?
          status = repo.statuses[filePath]
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

        @div path.basename(filePath), class: "primary-line file icon #{typeClass}"
        @div projectRelativePath, class: 'secondary-line path no-icon'

  openPath: (filePath, lineNumber) ->
    return unless filePath

    atom.workspaceView.open(filePath, {@allowActiveEditorChange}).done =>
      @moveToLine(lineNumber)

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

  confirmed : ({filePath}) ->
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
