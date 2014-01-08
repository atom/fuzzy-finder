{$} = require 'atom'
humanize = require 'humanize-plus'

FuzzyFinderView = require './fuzzy-finder-view'
PathLoader = require './path-loader'

module.exports =
class ProjectView extends FuzzyFinderView
  projectPaths: null
  reloadProjectPaths: true

  initialize: (@projectPaths) ->
    super

    @reloadProjectPaths = false if @projectPaths?.length > 0

    @subscribe $(window), 'focus', => @reloadProjectPaths = true
    @observeConfig 'fuzzy-finder.ignoredNames', => @reloadProjectPaths = true

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
    if @projectPaths?
      @setArray(@projectPaths)

    if @reloadProjectPaths
      @reloadProjectPaths = false
      @setLoading("Indexing project...")
      @loadingBadge.text("0")

      @loadPathsTask?.terminate()
      @loadPathsTask = PathLoader.startTask (paths) =>
        @projectPaths = paths
        @populate()

      pathsFound = 0
      @loadPathsTask.on 'load-paths:paths-found', (paths) =>
        pathsFound += paths.length
        @loadingBadge.text(humanize.intComma(pathsFound))

  beforeRemove: ->
    @loadPathsTask?.terminate()
