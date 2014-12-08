path = require 'path'
fs = require 'fs-plus'
FuzzyFinderView = require './fuzzy-finder-view'

module.exports =
class GitStatusView extends FuzzyFinderView
  toggle: ->
    if @panel?.isVisible()
      @cancel()
    else if atom.project.getRepositories()[0]?
      @populate()
      @show()

  getEmptyMessage: (itemCount) ->
    if itemCount is 0
      'Nothing to commit, working directory clean'
    else
      super

  populate: ->
    paths = []
    workingDirectory = atom.project.getRepositories()[0].getWorkingDirectory()
    for filePath, status of atom.project.getRepositories()[0].statuses
      filePath = path.join(workingDirectory, filePath)
      paths.push(filePath) if fs.isFileSync(filePath)

    @setItems(paths)
