fs = require 'fs'
path = require 'path'
_ = require 'underscore-plus'
{Git} = require 'atom'
{Minimatch} = require 'minimatch'

asyncCallsInProgress = 0
pathsChunkSize = 100
paths = []
repo = null
ignoredNames = null
traverseSymlinkDirectories = false
callback = null

isIgnored = (loadedPath) ->
  if repo?.isPathIgnored(loadedPath)
    true
  else
    for ignoredName in ignoredNames
      return true if ignoredName.match(loadedPath)

asyncCallStarting = ->
  asyncCallsInProgress++

asyncCallDone = ->
  if --asyncCallsInProgress is 0
    repo?.destroy()
    emit('load-paths:paths-found', paths)
    callback()

pathLoaded = (path) ->
  paths.push(path) unless isIgnored(path)
  if paths.length is pathsChunkSize
    emit('load-paths:paths-found', paths)
    paths = []

loadPath = (path) ->
  asyncCallStarting()
  fs.lstat path, (error, stats) ->
    unless error?
      if stats.isSymbolicLink()
        asyncCallStarting()
        fs.stat path, (error, stats) ->
          unless error?
            if stats.isFile()
              pathLoaded(path)
            else if stats.isDirectory() and traverseSymlinkDirectories
              loadFolder(path) unless isIgnored(path)
          asyncCallDone()
      else if stats.isDirectory()
        loadFolder(path) unless isIgnored(path)
      else if stats.isFile()
        pathLoaded(path)
    asyncCallDone()

loadFolder = (folderPath) ->
  asyncCallStarting()
  fs.readdir folderPath, (error, children=[]) ->
    loadPath(path.join(folderPath, childName)) for childName in children
    asyncCallDone()

module.exports = (rootPath, traverseIntoSymlinkDirectories, ignoreVcsIgnores, ignores=[]) ->
  traverseSymlinkDirectories = traverseIntoSymlinkDirectories
  ignoredNames = []
  for ignore in ignores when ignore
    try
      ignoredNames.push(new Minimatch(ignore, matchBase: true, dot: true))
    catch error
      console.warn "Error parsing ignore pattern (#{ignore}): #{error.message}"

  callback = @async()
  repo = Git.open(rootPath, refreshOnWindowFocus: false) if ignoreVcsIgnores
  loadFolder(rootPath)
