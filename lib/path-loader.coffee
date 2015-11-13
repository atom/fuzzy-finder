{Task} = require 'atom'

module.exports =
  startTask: (callback) ->
    projectPaths = []
    taskPath = require.resolve('./load-paths-handler')

    ignoredNames = atom.config.get('fuzzy-finder.ignoredNames') ? []
    ignoredNames = ignoredNames.concat(atom.config.get('core.ignoredNames') ? [])

    options =
      excludeVcsIgnores: atom.config.get 'core.excludeVcsIgnoredPaths'
      exclusions: ignoredNames
      follow: atom.config.get 'core.followSymlinks'

    task = Task.once(
      taskPath,
      atom.project.getPaths(),
      options,
      -> callback(projectPaths)
    )

    task.on 'load-paths:paths-found', (paths) ->
      projectPaths.push(paths...)

    task
