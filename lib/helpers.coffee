path = require "path"

module.exports =
  repositoryForPath: (filePath) ->
    for projectPath, i in atom.project.getPaths()
      if filePath is projectPath or filePath.startsWith(projectPath + path.sep)
        return atom.project.getRepositories()[i]
    return null
