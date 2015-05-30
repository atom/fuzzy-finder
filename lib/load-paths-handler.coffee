async = require 'async'
fs = require 'fs'
path = require 'path'
_ = require 'underscore-plus'
{GitRepository} = require 'atom'
{Minimatch} = require 'minimatch'

PathsChunkSize = 100

class PathLoader
  constructor: (@rootPath, ignoreVcsIgnores, @traverseSymlinkDirectories, @ignoredNames) ->
    @repo = null
    if ignoreVcsIgnores
      repo = GitRepository.open(@rootPath, refreshOnWindowFocus: false)
      @repo = repo if repo?.relativize(path.join(@rootPath, 'test')) is 'test'

  load: (done) ->
    @loadPath @rootPath, =>
      @repo?.destroy()
      done()

  emitPaths: (paths) ->
    emit('load-paths:paths-found', paths)

  isPathIgnored: (pathStr) ->
    relativePath = path.relative(@rootPath, pathStr)
    if @repo?.isPathIgnored(relativePath)
      return true
    else
      for ignoredName in @ignoredNames
        return true if ignoredName.match(relativePath)

  loadPath: (pathToLoad, done) ->
    visitedDirs = {};
    paths = [];
    counter = 0;

    appendPath = (path) =>
      paths[counter] = path
      counter = (counter + 1) % PathsChunkSize
      @emitPaths paths if counter == 0
      return

    traverseRecursively = (root, realRoot) =>
      try
        children = fs.readdirSync root
      catch error
        return
      for child in children
        childPath = path.join root, child
        if @isPathIgnored childPath
          continue
        try
          fileStat = fs.lstatSync childPath
        catch error
          continue
        if fileStat.isSymbolicLink()
          try
            symlinkTargetStat = fs.statSync childPath
          catch error
            continue
          try
            childRealPath = fs.realpathSync childPath
          catch error
            continue
          if symlinkTargetStat.isFile() && childRealPath.startsWith(realPathToLoad)
            continue
          else if symlinkTargetStat.isDirectory() && !@traverseSymlinkDirectories
            continue
          fileStat = symlinkTargetStat
        else
          childRealPath = childPath
        if fileStat.isDirectory()
          if childRealPath of visitedDirs
            continue
          else
            visitedDirs[childRealPath] = true
            traverseRecursively childPath
        else if fileStat.isFile()
          appendPath childPath
      return

    realPathToLoad = fs.realpathSync pathToLoad
    traverseRecursively pathToLoad, realPathToLoad

    paths.length = counter
    @emitPaths paths if paths.length

    return done()


module.exports = (rootPaths, followSymlinks, ignoreVcsIgnores, ignores=[]) ->
  ignoredNames = []
  for ignore in ignores when ignore
    try
      ignoredNames.push(new Minimatch(ignore, matchBase: true, dot: true))
    catch error
      console.warn "Error parsing ignore pattern (#{ignore}): #{error.message}"

  async.each(
    rootPaths.reverse(),
    (rootPath, next) ->
      new PathLoader(
        rootPath,
        ignoreVcsIgnores,
        followSymlinks,
        ignoredNames
      ).load(next)
    @async()
  )
