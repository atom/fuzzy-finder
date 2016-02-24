fs = require 'fs-plus'
{Task} = require 'atom'

module.exports =
  startTask: (callback) ->
    results = []
    taskPath = require.resolve('./load-paths-handler')
    followSymlinks = atom.config.get 'core.followSymlinks'
    ignoredNames = atom.config.get('fuzzy-finder.ignoredNames') ? []
    ignoredNames = ignoredNames.concat(atom.config.get('core.ignoredNames') ? [])
    ignoreVcsIgnores = atom.config.get('core.excludeVcsIgnoredPaths')
    projectPaths = atom.project.getPaths().map((path) => fs.realpathSync(path))

    task = Task.once(
      taskPath,
      projectPaths,
      followSymlinks,
      ignoreVcsIgnores,
      ignoredNames, ->
        callback(results)
    )

    task.on 'load-paths:paths-found', (paths) ->
      results.push(paths...)

    task
