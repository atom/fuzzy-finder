{$} = require 'atom'
humanize = require 'humanize-plus'

FuzzyFinderView = require './fuzzy-finder-view'
PathLoader = require './path-loader'

module.exports =
class ProjectView extends FuzzyFinderView
  paths: null
  reloadPaths: true

  initialize: (@paths) ->
    super

    @reloadPaths = false if @paths?.length > 0

    @subscribe $(window), 'focus', =>
      @reloadPaths = true
    @subscribe atom.config.observe 'fuzzy-finder.ignoredNames', callNow: false, =>
      @reloadPaths = true

  toggle: ->
    if @hasParent()
      @cancel()
    else if atom.project.getPath()?
      @populate()
      @attach()

  getEmptyMessage: (itemCount) ->
    if itemCount is 0
      'Project is empty'
    else
      super

  populate: ->
    if @paths?
      @setItems(@paths)

    if @reloadPaths
      @reloadPaths = false
      @loadPathsTask?.terminate()
      @loadPathsTask = PathLoader.startTask (@paths) => @populate()

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
      for {filePath}, index in @projectRelativePaths
        if filePath is lastOpenedPath
          projectRelativePaths.splice(index, 1)
          break

      projectRelativePath = atom.project.relativize(lastOpenedPath)
      lastOpenedEntry = {filePath: lastOpenedPath, projectRelativePath}
      projectRelativePaths.unshift(lastOpenedEntry)

    projectRelativePaths

  getLastOpenedPath: ->
    activePath = atom.workspace.activePaneItem?.getPath?()

    lastOpenedEditor = null

    for editor in atom.project.getEditors()
      filePath = editor.getPath()
      continue unless filePath
      continue if activePath is filePath

      lastOpenedEditor ?= editor
      if editor.lastOpened > lastOpenedEditor.lastOpened
        lastOpenedEditor = editor

    lastOpenedEditor?.getPath()

  beforeRemove: ->
    @loadPathsTask?.terminate()
