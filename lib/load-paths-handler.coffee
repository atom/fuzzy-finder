async = require 'async'
fs = require 'fs'
path = require 'path'
_ = require 'underscore-plus'
{GitRepository} = require 'atom'
{Minimatch} = require 'minimatch'
{GitProcess} = require 'dugite'

PathsChunkSize = 100

emittedPaths = new Set

class PathLoader
  constructor: (@rootPath, @ignoreVcsIgnores, @traverseSymlinkDirectories, @ignoredNames) ->
    @paths = []
    @realPathCache = {}

  load: (done) ->
    repo = GitRepository.open(@rootPath, refreshOnWindowFocus: false)
    if repo?.relativize(path.join(@rootPath, 'test')) is 'test'
      args = ['ls-files', '-c', '-o', '-z']
      if @ignoreVcsIgnores
        args.push('--exclude-standard')
      for ignoredName in @ignoredNames
        args.push("-x")
        args.push(ignoredName.pattern)
      output = ""
      proc = GitProcess.spawn(args, @rootPath)
      proc.stdout.on 'data', (chunk) ->
        files = (output + chunk).split("\0")
        output = files.pop()
        emit('load-paths:paths-found', files)
      proc.on "close", (code) ->
        repo?.destroy()
        done()
    else
      @loadPath @rootPath, true, =>
        @flushPaths()
        repo?.destroy()
        done()

  isIgnored: (loadedPath) ->
    relativePath = path.relative(@rootPath, loadedPath)
    for ignoredName in @ignoredNames
      return true if ignoredName.match(relativePath)

  pathLoaded: (loadedPath, done) ->
    unless @isIgnored(loadedPath) or emittedPaths.has(loadedPath)
      @paths.push(loadedPath)
      emittedPaths.add(loadedPath)

    if @paths.length is PathsChunkSize
      @flushPaths()
    done()

  flushPaths: ->
    emit('load-paths:paths-found', @paths)
    @paths = []

  loadPath: (pathToLoad, root, done) ->
    return done() if @isIgnored(pathToLoad) and not root
    fs.lstat pathToLoad, (error, stats) =>
      return done() if error?
      if stats.isSymbolicLink()
        @isInternalSymlink pathToLoad, (isInternal) =>
          return done() if isInternal
          fs.stat pathToLoad, (error, stats) =>
            return done() if error?
            if stats.isFile()
              @pathLoaded(pathToLoad, done)
            else if stats.isDirectory()
              if @traverseSymlinkDirectories
                @loadFolder(pathToLoad, done)
              else
                done()
            else
              done()
      else if stats.isDirectory()
        @loadFolder(pathToLoad, done)
      else if stats.isFile()
        @pathLoaded(pathToLoad, done)
      else
        done()

  loadFolder: (folderPath, done) ->
    fs.readdir folderPath, (error, children=[]) =>
      async.each(
        children,
        (childName, next) =>
          @loadPath(path.join(folderPath, childName), false, next)
        done
      )

  isInternalSymlink: (pathToLoad, done) ->
    fs.realpath pathToLoad, @realPathCache, (err, realPath) =>
      if err
        done(false)
      else
        done(realPath.search(@rootPath) is 0)

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
