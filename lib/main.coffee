module.exports =
  configDefaults:
    ignoredNames: []
    traverseIntoSymlinkDirectories: false

  activate: (state) ->
    atom.workspaceView.command 'fuzzy-finder:toggle-file-finder', =>
      @createProjectView().toggle()
    atom.workspaceView.command 'fuzzy-finder:toggle-buffer-finder', =>
      @createBufferView().toggle()
    atom.workspaceView.command 'fuzzy-finder:toggle-git-status-finder', =>
      @createGitStatusView().toggle()

    if atom.project.getPath()?
      PathLoader = require './path-loader'
      @loadPathsTask = PathLoader.startTask (paths) => @projectPaths = paths

    for editor in atom.workspace.getTextEditors()
      editor.lastOpened = state[editor.getPath()]

    atom.workspaceView.eachPaneView (paneView) ->
      paneView.activeItem?.lastOpened = Date.now()
      paneView.on 'pane:active-item-changed', (e, item) -> item.lastOpened = Date.now()

  deactivate: ->
    if @loadPathsTask?
      @loadPathsTask.terminate()
      @loadPathsTask = null
    if @projectView?
      @projectView.destroy()
      @projectView = null
    if @bufferView?
      @bufferView.destroy()
      @bufferView = null
    if @gitStatusView?
      @gitStatusView.destroy()
      @gitStatusView = null
    @projectPaths = null

  serialize: ->
    paths = {}
    for editor in atom.workspace.getTextEditors()
      path = editor.getPath()
      paths[path] = editor.lastOpened if path?
    paths

  createProjectView:  ->
    unless @projectView?
      @loadPathsTask?.terminate()
      ProjectView  = require './project-view'
      @projectView = new ProjectView(@projectPaths)
      @projectPaths = null
    @projectView

  createGitStatusView:  ->
    unless @gitStatusView?
      GitStatusView  = require './git-status-view'
      @gitStatusView = new GitStatusView()
    @gitStatusView

  createBufferView: ->
    unless @bufferView?
      BufferView = require './buffer-view'
      @bufferView = new BufferView()
    @bufferView
