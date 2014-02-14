{_} = require 'atom'
FuzzyFinderView = require './fuzzy-finder-view'

module.exports =
class BufferView extends FuzzyFinderView
  toggle: ->
    if @hasParent()
      @cancel()
    else
      @allowActiveEditorChange = true
      @populate()
      @attach() if @paths?.length > 0

  getEmptyMessage: (itemCount) ->
    if itemCount is 0
      'No open editors'
    else
      super

  populate: ->
    editors = atom.project.getEditors().filter (editor) -> editor.getPath()?
    editors = _.sortBy editors, (editor) ->
      if editor is atom.workspaceView.getActivePaneItem()
        0
      else
        -(editor.lastOpened or 1)

    @paths = []
    @paths.push(editor.getPath()) for editor in editors

    @setItems(_.uniq(@paths))
