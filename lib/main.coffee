module.exports =
  config:
    ignoredNames:
      type: 'array'
      default: []

  activate: (state) ->
    @active = true

    atom.commands.add 'atom-workspace',
      'fuzzy-finder:toggle-file-finder': =>
        @createProjectView().toggle()
      'fuzzy-finder:toggle-buffer-finder': =>
        @createBufferView().toggle()
      'fuzzy-finder:toggle-git-status-finder': =>
        @createGitStatusView().toggle()

    if atom.project.getPaths().length > 0
      process.nextTick => @startLoadPathsTask()

    for editor in atom.workspace.getTextEditors()
      editor.lastOpened = state[editor.getPath()]

    atom.workspace.observePanes (pane) ->
      pane.observeActiveItem (item) -> item?.lastOpened = Date.now()

  deactivate: ->
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
    @stopLoadPathsTask()
    @active = false

  serialize: ->
    paths = {}
    for editor in atom.workspace.getTextEditors()
      path = editor.getPath()
      paths[path] = editor.lastOpened if path?
    paths

  createProjectView:  ->
    @stopLoadPathsTask()

    unless @projectView?
      ProjectView  = require './project-view'
      @projectView = new ProjectView(@projectPaths)
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

  startLoadPathsTask: ->
    @stopLoadPathsTask()

    return unless @active
    PathLoader = require './path-loader'
    @loadPathsTask = PathLoader.startTask (@projectPaths) =>

  stopLoadPathsTask: ->
    @loadPathsTask?.terminate()
    @loadPathsTask = null
