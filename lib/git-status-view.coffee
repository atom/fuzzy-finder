path = require 'path'
fs = require 'fs-plus'
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
    workingDirectory = atom.project.getRepo().getWorkingDirectory()
    for filePath, status of atom.project.getRepo().statuses
      filePath = path.join(workingDirectory, filePath)
      paths.push(filePath) if fs.isFileSync(filePath)

    @setItems(paths)
