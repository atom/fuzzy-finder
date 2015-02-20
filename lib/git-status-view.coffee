path = require 'path'
fs = require 'fs-plus'
FuzzyFinderView = require './fuzzy-finder-view'

module.exports =
class GitStatusView extends FuzzyFinderView
  toggle: ->
    if @panel?.isVisible()
      @cancel()
    else if atom.project.getRepositories().some((repo) -> repo?)
      @populate()
      @show()

  getEmptyMessage: (itemCount) ->
    if itemCount is 0
      'Nothing to commit, working directory clean'
    else
      super

  populate: ->
    paths = []
    for repo in atom.project.getRepositories() when repo?
      workingDirectory = repo.getWorkingDirectory()
      for filePath of repo.statuses
        filePath = path.join(workingDirectory, filePath)
        paths.push(filePath) if fs.isFileSync(filePath)
    @setItems(paths)
