{$} = require 'atom'
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

    @reloadPaths = false if @paths?.length > 0

    @subscribe $(window), 'focus', =>
      if @paths?
        @reloadPaths = true
      else
        # The window gained focused while the first task was still running
        # so let it complete but reload the paths on the next populate call.
        @reloadAfterFirstLoad = true

    @subscribeToConfig()

    @subscribe atom.project, 'path-changed', =>
      @reloadPaths = true
      @paths = null

  subscribeToConfig: ->
    @subscribe atom.config.onDidChange 'fuzzy-finder.ignoredNames', =>
      @reloadPaths = true

    @subscribe atom.config.onDidChange 'fuzzy-finder.traverseIntoSymlinkDirectories', =>
      @reloadPaths = true

    @subscribe atom.config.onDidChange 'core.ignoredNames', =>
      @reloadPaths = true

    @subscribe atom.config.onDidChange 'core.excludeVcsIgnoredPaths', =>
      @reloadPaths = true

  toggle: ->
    if @hasParent()
      @cancel()
    else
      @populate()
      @attach()

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
    activePath = atom.workspace.activePaneItem?.getPath?()

    lastOpenedEditor = null

    for editor in atom.workspace.getTextEditors()
      filePath = editor.getPath()
      continue unless filePath
      continue if activePath is filePath

      lastOpenedEditor ?= editor
      if editor.lastOpened > lastOpenedEditor.lastOpened
        lastOpenedEditor = editor

    lastOpenedEditor?.getPath()

  beforeRemove: ->
    @loadPathsTask?.terminate()
