{Task} = require 'atom'

module.exports =
  startTask: (callback) ->
    projectPaths = []
    taskPath = require.resolve('./load-paths-handler')
    ignoredNames = atom.config.get('fuzzy-finder.ignoredNames') ? []
    ignoredNames = ignoredNames.concat(atom.config.get('core.ignoredNames') ? [])
    ignoreVcsIgnores = atom.config.get('core.excludeVcsIgnoredPaths') and atom.project?.getRepo()?.isProjectAtRoot()

    task = Task.once taskPath, atom.project.getPath(), ignoreVcsIgnores, ignoredNames, ->
      callback(projectPaths)

    task.on 'load-paths:paths-found', (paths) ->
      projectPaths.push(paths...)

    task
