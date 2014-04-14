_ = require 'underscore-plus'
FuzzyFinderView = require './fuzzy-finder-view'

module.exports =
class BufferView extends FuzzyFinderView
  toggle: ->
    if @hasParent()
      @cancel()
    else
      @populate()
      @attach() if @paths?.length > 0

  getEmptyMessage: (itemCount) ->
    if itemCount is 0
      'No open editors'
    else
      super

  populate: ->
    editors = atom.workspace.getEditors().filter (editor) -> editor.getPath()?
    editors = _.sortBy editors, (editor) ->
      if editor is atom.workspaceView.getActivePaneItem()
        0
      else
        -(editor.lastOpened or 1)

    @paths = editors.map (editor) -> editor.getPath()
    @setItems(_.uniq(@paths))
