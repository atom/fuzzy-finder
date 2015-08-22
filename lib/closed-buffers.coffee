{CompositeDisposable} = require 'atom'
_ = require 'underscore-plus'

module.exports =
class ClosedBuffers
  constructor: ->
    @items = {}
    @disposables = new CompositeDisposable

    @disposables.add atom.workspace.onDidDestroyPaneItem ({item}) =>
      @ifItemHasPath item, (path, item) =>
        @addPath(path, item.lastOpened)

    @disposables.add atom.workspace.onDidOpen ({item}) =>
      @ifItemHasPath item, (path) =>
        @deletePath(path)

    @disposables.add atom.config.observe 'fuzzy-finder.maxClosedBuffersToRemember', (max) =>
      @limitPathsToRemember(max)

  ifItemHasPath: (item, fn) ->
    path = item.getPath?()
    if path
      fn(path, item)

  addPath: (path, lastOpened) ->
    limit = atom.config.get('fuzzy-finder.maxClosedBuffersToRemember')
    if limit > 0
      @items[path] = Date.now()
      @limitPathsToRemember(limit)

  deletePath: (path) ->
    delete @items[path]

  limitPathsToRemember: (max) ->
    keys = _.keys(@items)
    overflow = keys.length - max
    if overflow > 0
      _.times overflow, (i) =>
        @deletePath(keys[i])

  dispose: ->
    @disposables.dispose()
