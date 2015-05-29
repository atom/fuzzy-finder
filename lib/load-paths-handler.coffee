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

    statOrLstatSync = if @traverseSymlinkDirectories then fs.statSync else fs.lstatSync

    appendPath = (path) =>
      paths[counter] = path
      counter = (counter + 1) % PathsChunkSize
      @emitPaths paths if counter == 0
      return

    traverseRecursively = (root) =>
      try
        children = fs.readdirSync root
      catch error
        return
      for child in children
        childPath = path.join root, child
        if @isPathIgnored childPath
          continue
        try
          fileStat = statOrLstatSync childPath
        catch error
          continue
        if fileStat.isSymbolicLink()
          symlinkTargetStat = fs.statSync childPath
          appendPath childPath if symlinkTargetStat.isFile()
        else if fileStat.isDirectory()
          try
            childRealPath = fs.realpathSync childPath
          catch error
            continue
          if childRealPath of visitedDirs
            continue
          else
            visitedDirs[childRealPath] = true
            traverseRecursively childPath
        else if fileStat.isFile()
          appendPath childPath
      return

    traverseRecursively pathToLoad

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
    rootPaths,
    (rootPath, next) ->
      new PathLoader(
        rootPath,
        ignoreVcsIgnores,
        followSymlinks,
        ignoredNames
      ).load(next)
    @async()
  )
