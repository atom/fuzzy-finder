path = require "path"

module.exports =
  splitProjectPath: (filePath) ->
    for projectPath in atom.project.getPaths()
      if filePath is projectPath or filePath.startsWith(projectPath + path.sep)
        return [projectPath, path.relative(projectPath, filePath)]
    return [null, filePath]
