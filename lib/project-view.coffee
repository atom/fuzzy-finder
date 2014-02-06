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
      @setArray(@paths)

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

  beforeRemove: ->
    @loadPathsTask?.terminate()
