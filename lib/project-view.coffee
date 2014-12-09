{$} = require 'atom-space-pen-views'
{Disposable, CompositeDisposable} = require 'atom'
humanize = require 'humanize-plus'

FuzzyFinderView = require './fuzzy-finder-view'
PathLoader = require './path-loader'

module.exports =
class ProjectView extends FuzzyFinderView
  paths: null
  reloadPaths: true
  reloadAfterFirstLoad: false

  initialize: (@paths) ->
    super

    @disposables = new CompositeDisposable

    @reloadPaths = false if @paths?.length > 0

    windowFocused = =>
      if @paths?
        @reloadPaths = true
      else
        # The window gained focused while the first task was still running
        # so let it complete but reload the paths on the next populate call.
        @reloadAfterFirstLoad = true

    window.addEventListener('focus', windowFocused)
    @disposables.add new Disposable -> window.removeEventListener('focus', windowFocused)

    @subscribeToConfig()

    @disposables.add atom.project.onDidChangePaths =>
      @reloadPaths = true
      @paths = null

  subscribeToConfig: ->
    @disposables.add atom.config.onDidChange 'fuzzy-finder.ignoredNames', =>
      @reloadPaths = true

    @disposables.add atom.config.onDidChange 'fuzzy-finder.traverseIntoSymlinkDirectories', =>
      @reloadPaths = true

    @disposables.add atom.config.onDidChange 'core.ignoredNames', =>
      @reloadPaths = true

    @disposables.add atom.config.onDidChange 'core.excludeVcsIgnoredPaths', =>
      @reloadPaths = true

  toggle: ->
    if @panel?.isVisible()
      @cancel()
    else
      @populate()
      @show()

  getEmptyMessage: (itemCount) ->
    if itemCount is 0
      'Project is empty'
    else
      super

  populate: ->
    @setItems(@paths) if @paths?

    unless atom.project.getPaths()[0]?
      @setItems([])
      return

    if @reloadPaths
      @reloadPaths = false
      @loadPathsTask?.terminate()
      @loadPathsTask = PathLoader.startTask (@paths) =>
        if @reloadAfterFirstLoad
          @reloadPaths = true
          @reloadAfterFirstLoad = false

        @populate()

      if @paths?
        @setLoading("Reindexing project\u2026")
      else
        @setLoading("Indexing project\u2026")
        @loadingBadge.text('0')
        pathsFound = 0
        @loadPathsTask.on 'load-paths:paths-found', (paths) =>
          pathsFound += paths.length
          @loadingBadge.text(humanize.intComma(pathsFound))

  projectRelativePathsForFilePaths: ->
    projectRelativePaths = super

    if lastOpenedPath = @getLastOpenedPath()
      lastOpenedProjectRelativePath = atom.project.relativize(lastOpenedPath)
      for {projectRelativePath}, index in projectRelativePaths
        if lastOpenedProjectRelativePath is projectRelativePath
          projectRelativePaths.splice(index, 1)
          break

      projectRelativePaths.unshift
        filePath: lastOpenedPath
        projectRelativePath: lastOpenedProjectRelativePath

    projectRelativePaths

  getLastOpenedPath: ->
    activePath = atom.workspace.getActivePaneItem()?.getPath?()

    lastOpenedEditor = null

    for editor in atom.workspace.getTextEditors()
      filePath = editor.getPath()
      continue unless filePath
      continue if activePath is filePath

      lastOpenedEditor ?= editor
      if editor.lastOpened > lastOpenedEditor.lastOpened
        lastOpenedEditor = editor

    lastOpenedEditor?.getPath()

  destroy: ->
    @loadPathsTask?.terminate()
    @disposables.dispose()
    super
