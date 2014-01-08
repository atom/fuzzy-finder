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

    @subscribe $(window), 'focus', => @reloadPaths = true
    @observeConfig 'fuzzy-finder.ignoredNames', => @reloadPaths = true

  toggle: ->
    if @hasParent()
      @cancel()
    else if atom.project.getPath()?
      @allowActiveEditorChange = false
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
      @setLoading("Indexing project...")
      @loadingBadge.text("0")

      @loadPathsTask?.terminate()
      @loadPathsTask = PathLoader.startTask (@paths) => @populate()

      pathsFound = 0
      @loadPathsTask.on 'load-paths:paths-found', (paths) =>
        pathsFound += paths.length
        @loadingBadge.text(humanize.intComma(pathsFound))

  beforeRemove: ->
    @loadPathsTask?.terminate()
