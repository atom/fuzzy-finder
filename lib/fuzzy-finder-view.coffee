{_, $, $$, fs, Point, SelectList, View} = require 'atom'
humanize = require 'humanize-plus'
path = require 'path'
PathLoader = require './path-loader'

module.exports =
class FuzzyFinderView extends SelectList
  filenameRegex: /[\w\.\-\/\\]+/
  finderMode: null

  @viewClass: ->
    [super, 'fuzzy-finder', 'overlay', 'from-top'].join(' ')

  allowActiveEditorChange: null
  maxItems: 10
  projectPaths: null
  reloadProjectPaths: true
  filterKey: 'projectRelativePath'

  initialize: (@projectPaths) ->
    super

    @reloadProjectPaths = false if @projectPaths?.length > 0

    @subscribe $(window), 'focus', => @reloadProjectPaths = true
    @observeConfig 'fuzzy-finder.ignoredNames', => @reloadProjectPaths = true
    atom.workspaceView.eachPane (pane) ->
      pane.activeItem?.lastOpened = Date.now() - 1
      pane.on 'pane:active-item-changed', (e, item) -> item.lastOpened = (new Date) - 1

    @miniEditor.command 'pane:split-left', =>
      @splitOpenPath (pane, session) -> pane.splitLeft(session)
    @miniEditor.command 'pane:split-right', =>
      @splitOpenPath (pane, session) -> pane.splitRight(session)
    @miniEditor.command 'pane:split-down', =>
      @splitOpenPath (pane, session) -> pane.splitDown(session)
    @miniEditor.command 'pane:split-up', =>
      @splitOpenPath (pane, session) -> pane.splitUp(session)

  itemForElement: ({filePath, projectRelativePath}) ->
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

    if editor = atom.workspaceView.getActiveView()
      position = new Point(lineNumber)
      editor.scrollToBufferPosition(position, center: true)
      editor.setCursorBufferPosition(position)
      editor.moveCursorToFirstCharacterOfLine()

  splitOpenPath: (fn) ->
    {filePath} = @getSelectedElement()
    return unless filePath

    lineNumber = @getLineNumber()
    if pane = atom.workspaceView.getActivePane()
      atom.project.open(filePath).done (editSession) =>
        fn(pane, editSession)
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

  toggleFileFinder: ->
    @finderMode = 'file'
    if @hasParent()
      @cancel()
    else
      return unless atom.project.getPath()?
      @allowActiveEditorChange = false
      @populateProjectPaths()
      @attach()

  toggleBufferFinder: ->
    @finderMode = 'buffer'
    if @hasParent()
      @cancel()
    else
      @allowActiveEditorChange = true
      @populateOpenBufferPaths()
      @attach() if @paths?.length

  toggleGitFinder: ->
    @finderMode = 'git'
    if @hasParent()
      @cancel()
    else
      return unless atom.project.getRepo()?
      @allowActiveEditorChange = false
      @populateGitStatusPaths()
      @attach()

  getEmptyMessage: (itemCount) ->
    if itemCount is 0
      switch @finderMode
        when 'git'
          'Nothing to commit, working directory clean'
        when 'buffer'
          'No open editors'
        when 'file'
          'Project is empty'
        else
          super
    else
      super

  getFilterQuery: ->
    query = super
    colon = query.indexOf(':')
    if colon is -1
      query
    else
      query[0...colon]

  getLineNumber: ->
    query = @miniEditor.getText()
    colon = query.indexOf(':')
    if colon is -1
      -1
    else
      parseInt(query[colon+1..]) - 1

  setArray: (paths) ->
    projectRelativePaths = paths.map (filePath) ->
      projectRelativePath = atom.project.relativize(filePath)
      {filePath, projectRelativePath}

    super(projectRelativePaths)

  populateGitStatusPaths: ->
    paths = []
    paths.push(filePath) for filePath, status of atom.project.getRepo().statuses when fs.isFileSync(filePath)

    @setArray(paths)

  populateProjectPaths: ->
    if @projectPaths?
      @setArray(@projectPaths)

    if @reloadProjectPaths
      @reloadProjectPaths = false
      @setLoading("Indexing project...")
      @loadingBadge.text("0")

      @loadPathsTask?.terminate()
      @loadPathsTask = PathLoader.startTask (paths) =>
        @projectPaths = paths
        @populateProjectPaths()

      pathsFound = 0
      @loadPathsTask.on 'load-paths:paths-found', (paths) =>
        pathsFound += paths.length
        @loadingBadge.text(humanize.intComma(pathsFound))

  populateOpenBufferPaths: ->
    editSessions = atom.project.getEditors().filter (editSession) ->
      editSession.getPath()?

    editSessions = _.sortBy editSessions, (editSession) =>
      if editSession is atom.workspaceView.getActivePaneItem()
        0
      else
        -(editSession.lastOpened or 1)

    @paths = []
    @paths.push(editSession.getPath()) for editSession in editSessions

    @setArray(_.uniq(@paths))

  beforeRemove: ->
    @loadPathsTask?.terminate()

  attach: ->
    super

    atom.workspaceView.append(this)
    @miniEditor.focus()
