_ = require 'underscore-plus'
FuzzyFinderView = require './fuzzy-finder-view'

module.exports =
class BufferView extends FuzzyFinderView

  initialize: (@closedBuffers) ->
    super

  toggle: ->
    if @panel?.isVisible()
      @cancel()
    else
      @populate()
      @show() if @paths?.length > 0

  getEmptyMessage: (itemCount) ->
    if itemCount is 0
      'No open editors'
    else
      super

  populate: ->
    editors = atom.workspace.getTextEditors().filter (editor) -> editor.getPath()?
    activeEditor = atom.workspace.getActiveTextEditor()

    # Create a list of closed editors, matching the item data structure of editors list
    closedEditors = _.map @closedBuffers.items, (dateClosed, path) ->
      lastOpened: dateClosed
      getPath: -> path

    @paths = _.chain(editors.concat(closedEditors))
      .sortBy (editor) ->
        if editor is activeEditor
          0
        else
          -(editor.lastOpened or 1)
      .map (editor) -> editor.getPath()
      .uniq()
      .value()

    @setItems(@paths)
