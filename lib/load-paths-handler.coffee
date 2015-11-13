async = require 'async'
path = require 'path'
_ = require 'underscore-plus'
GitUtils = require 'git-utils'
{PathSearcher, PathScanner, search} = require 'scandal'

module.exports = (rootPaths, options={}) ->
  pathsSearched = 0
  PATHS_COUNTER_SEARCHED_CHUNK = 100
  emittedPaths = new Set

  async.each(
    rootPaths,
    (rootPath, next) ->
      options2 = _.extend {}, options,
        inclusions: processPaths(rootPath, options.inclusions)
        globalExclusions: processPaths(rootPath, options.globalExclusions)

      if options.ignoreProjectParentVcsIgnores
        repo = GitUtils.open(rootPath)
        if repo and '' != repo.relativize(rootPath)
          options2.excludeVcsIgnores = false

      scanner = new PathScanner(rootPath, options2)

      paths = []

      scanner.on 'path-found', (path) ->
        unless emittedPaths.has(path)
          paths.push path
          emittedPaths.add(path)
          pathsSearched++
        if pathsSearched % PATHS_COUNTER_SEARCHED_CHUNK is 0
          emit('load-paths:paths-found', paths)
          paths = []
      scanner.on 'finished-scanning', ->
        emit('load-paths:paths-found', paths)
        next()
      scanner.scan()

    @async()
  )

processPaths = (rootPath, paths) ->
  return paths unless paths?.length > 0
  rootPathBase = path.basename(rootPath)
  results = []
  for givenPath in paths
    segments = givenPath.split(path.sep)
    firstSegment = segments.shift()
    results.push(givenPath)
    if firstSegment is rootPathBase
      if segments.length is 0
        results.push(path.join("**", "*"))
      else
        results.push(path.join(segments...))
  results
