{$} = require 'atom-space-pen-views'
{Disposable, CompositeDisposable} = require 'atom'
humanize = require 'humanize-plus'
fs = require 'fs-plus'
path = require 'path'
zlib = require 'zlib'

FuzzyFinderView = require './fuzzy-finder-view'
PathLoader = require './path-loader'

module.exports =
class ProjectView extends FuzzyFinderView
  paths: null
  reloadPaths: true
  reloadAfterFirstLoad: false

  initialize: (@paths) ->
    super

    @disposables = new CompositeDisposable
    @reloadPaths = false if @paths?.length > 0

    windowFocused = =>
      if @paths?
        @reloadPaths = true
      else
        # The window gained focused while the first task was still running
        # so let it complete but reload the paths on the next populate call.
        @reloadAfterFirstLoad = true

    window.addEventListener('focus', windowFocused)
    @disposables.add new Disposable -> window.removeEventListener('focus', windowFocused)

    @subscribeToConfig()

    @disposables.add atom.project.onDidChangePaths =>
      @reloadPaths = true
      @paths = null

    if !@paths
      @tryLoadCachedProjectFiles()

    @cleanupOldFiles()

  subscribeToConfig: ->
    @disposables.add atom.config.onDidChange 'fuzzy-finder.ignoredNames', =>
      @reloadPaths = true

    @disposables.add atom.config.onDidChange 'core.followSymlinks', =>
      @reloadPaths = true

    @disposables.add atom.config.onDidChange 'core.ignoredNames', =>
      @reloadPaths = true

    @disposables.add atom.config.onDidChange 'core.excludeVcsIgnoredPaths', =>
      @reloadPaths = true

  toggle: ->
    if @panel?.isVisible()
      @cancel()
    else
      @populate()
      @show()

  getEmptyMessage: (itemCount) ->
    if itemCount is 0
      'Project is empty'
    else
      super

  populate: ->
    @setItems(@paths) if @paths?

    if atom.project.getPaths().length is 0
      @setItems([])
      return

    if @reloadPaths
      @reloadPaths = false

      try
        task = @runLoadPathsTask =>
          if @reloadAfterFirstLoad
            @reloadPaths = true
            @reloadAfterFirstLoad = false
          @populate()
      catch error
        # If, for example, a network drive is unmounted, @runLoadPathsTask will
        # throw ENOENT when it tries to get the realpath of all the project paths.
        # This catch block allows the file finder to still operate on the last
        # set of paths and still let the user know that something is wrong.
        if error.code is 'ENOENT' or error.code is 'EPERM'
          atom.notifications.addError('Project path not found!', detail: error.message)
        else
          throw error


      if @paths?
        @setLoading("Reindexing project\u2026")
      else
        @setLoading("Indexing project\u2026")
        @loadingBadge.text('0')
        pathsFound = 0
        task?.on 'load-paths:paths-found', (paths) =>
          pathsFound += paths.length
          @loadingBadge.text(humanize.intComma(pathsFound))

  projectRelativePathsForFilePaths: ->
    projectRelativePaths = super

    if lastOpenedPath = @getLastOpenedPath()
      for {filePath}, index in projectRelativePaths
        if filePath is lastOpenedPath
          [entry] = projectRelativePaths.splice(index, 1)
          projectRelativePaths.unshift(entry)
          break

    projectRelativePaths

  getLastOpenedPath: ->
    activePath = atom.workspace.getActivePaneItem()?.getPath?()

    lastOpenedEditor = null

    for editor in atom.workspace.getTextEditors()
      filePath = editor.getPath()
      continue unless filePath
      continue if activePath is filePath

      lastOpenedEditor ?= editor
      if editor.lastOpened > lastOpenedEditor.lastOpened
        lastOpenedEditor = editor

    lastOpenedEditor?.getPath()

  destroy: ->
    @loadPathsTask?.terminate()
    @disposables.dispose()
    super

  runLoadPathsTask: (fn) ->
    @loadPathsTask?.terminate()
    @loadPathsTask = PathLoader.startTask (newPaths) =>
      @reloadPaths = false
      changed = newPaths && @pathsChanged(@paths, newPaths)
      @paths = newPaths
      if changed
        @saveProjectData()
      fn?()

  pathsChanged: (oldPaths, newPaths) ->
    if (!oldPaths || oldPaths.length != newPaths.length)
      return true
    oldHash = {}
    for oldPath in oldPaths
      oldHash[oldPath] = true
    for newPath in newPaths
      if !oldHash[newPath]
        return true;
    return false;

  getBaseSavePath: ->
    packagePaths = atom.packages.getPackageDirPaths()
    path.join(packagePaths[packagePaths.length - 1], 'fuzzy-finder', 'data')

  getSavePath: (projectPath) ->
    path.join(@getBaseSavePath(), projectPath.replace(/\W+/g, '_'))

  saveProjectData: ->
    if !@paths?.length
      return
    atom.project.getPaths().map (projectPath) =>
      projectFilesPaths = @paths.filter((p) => p.startsWith projectPath)
      buffer = zlib.deflateSync(Buffer.from(JSON.stringify(projectFilesPaths)),
        { level: zlib.Z_BEST_SPEED })
      fs.writeFileSync(@getSavePath(projectPath), buffer)

  tryLoadCachedProjectFiles: ->
    atom.project.getPaths().forEach (projectPath) =>
      try
        buffer = zlib.inflateSync(fs.readFileSync(@getSavePath(projectPath)))
        data = JSON.parse(buffer.toString('utf8'))
        if data?.length
          @paths = if @paths then @paths.concat(data) else data

  cleanupOldFiles: ->
    basePath = @getBaseSavePath()
    new Promise (done) -> fs.readdir basePath, (err, files) ->
      if err || !files
        done()
      else
        promise = Promise.all files.map (file) ->
          filePath = path.join(basePath, file)
          new Promise (resolve) -> fs.stat filePath, (err, stats) ->
            if err || !stats
              return resolve()
            fileAgeDays = (Date.now() - stats.mtime) / 1000 / 3600 / 24
            if (fileAgeDays > 30)
              fs.unlink filePath, () -> resolve()
            else
              resolve()
        promise.then -> done()
