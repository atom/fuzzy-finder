{fs} = require 'atom'
FuzzyFinderView = require './fuzzy-finder-view'

module.exports =
class GitStatusView extends FuzzyFinderView
  toggle: ->
    if @hasParent()
      @cancel()
    else if atom.project.getRepo()?
      @populate()
      @attach()

  getEmptyMessage: (itemCount) ->
    if itemCount is 0
      'Nothing to commit, working directory clean'
    else
      super

  populate: ->
    paths = []
    for filePath, status of atom.project.getRepo().statuses
      paths.push(filePath) if fs.isFileSync(filePath)

    @setArray(paths)
