{Task} = require 'atom'

module.exports =
  startTask: (callback) ->
    projectPaths = []
    taskPath = require.resolve('./load-paths-handler')
    traverseIntoSymlinkDirectories = atom.config.get 'fuzzy-finder.traverseIntoSymlinkDirectories'
    ignoredNames = atom.config.get('fuzzy-finder.ignoredNames') ? []
    ignoredNames = ignoredNames.concat(atom.config.get('core.ignoredNames') ? [])
    ignoreVcsIgnores = atom.config.get('core.excludeVcsIgnoredPaths') and atom.project?.getRepositories()[0]?.isProjectAtRoot()

    task = Task.once taskPath, atom.project.getPaths()[0], traverseIntoSymlinkDirectories, ignoreVcsIgnores, ignoredNames, ->
      callback(projectPaths)

    task.on 'load-paths:paths-found', (paths) ->
      projectPaths.push(paths...)

    task
