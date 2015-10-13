net = require "net"
path = require 'path'
_ = require 'underscore-plus'
{$, $$} = require 'atom-space-pen-views'
fs = require 'fs-plus'
temp = require 'temp'
wrench = require 'wrench'

PathLoader = require '../lib/path-loader'

describe 'FuzzyFinder', ->
  [rootDir1, rootDir2] = []
  [fuzzyFinder, projectView, bufferView, gitStatusView, workspaceElement, fixturesPath] = []

  beforeEach ->
    rootDir1 = fs.realpathSync(temp.mkdirSync('root-dir1'))
    rootDir2 = fs.realpathSync(temp.mkdirSync('root-dir2'))

    fixturesPath = atom.project.getPaths()[0]

    wrench.copyDirSyncRecursive(
      path.join(fixturesPath, "root-dir1"),
      rootDir1,
      forceDelete: true
    )

    wrench.copyDirSyncRecursive(
      path.join(fixturesPath, "root-dir2"),
      rootDir2,
      forceDelete: true
    )

    atom.project.setPaths([rootDir1, rootDir2])

    workspaceElement = atom.views.getView(atom.workspace)

    waitsForPromise ->
      atom.workspace.open(path.join(rootDir1, 'sample.js'))

    waitsForPromise ->
      atom.packages.activatePackage('fuzzy-finder').then (pack) ->
        fuzzyFinder = pack.mainModule
        projectView = fuzzyFinder.createProjectView()
        bufferView = fuzzyFinder.createBufferView()
        gitStatusView = fuzzyFinder.createGitStatusView()

  dispatchCommand = (command) ->
    atom.commands.dispatch(workspaceElement, "fuzzy-finder:#{command}")

  waitForPathsToDisplay = (fuzzyFinderView) ->
    waitsFor "paths to display", 5000, ->
      fuzzyFinderView.list.children("li").length > 0

  eachFilePath = (dirPaths, fn) ->
    for dirPath in dirPaths
      findings = for filePath in wrench.readdirSyncRecursive(dirPath)
        fullPath = path.join(dirPath, filePath)
        if fs.isFileSync(fullPath)
          fn(filePath)
          true
      expect(findings).toContain(true)

  describe "file-finder behavior", ->
    beforeEach ->
      projectView.setMaxItems(Infinity)

    describe "toggling", ->
      describe "when the project has multiple paths", ->
        it "shows or hides the fuzzy-finder and returns focus to the active editor if it is already showing", ->
          jasmine.attachToDOM(workspaceElement)

          expect(atom.workspace.panelForItem(projectView)).toBeNull()
          atom.workspace.getActivePane().splitRight(copyActiveItem: true)
          [editor1, editor2] = atom.workspace.getTextEditors()

          dispatchCommand('toggle-file-finder')
          expect(atom.workspace.panelForItem(projectView).isVisible()).toBe true
          expect(projectView.filterEditorView).toHaveFocus()
          projectView.filterEditorView.getModel().insertText('this should not show up next time we toggle')

          dispatchCommand('toggle-file-finder')
          expect(atom.views.getView(editor1)).not.toHaveFocus()
          expect(atom.views.getView(editor2)).toHaveFocus()
          expect(atom.workspace.panelForItem(projectView).isVisible()).toBe false

          dispatchCommand('toggle-file-finder')
          expect(projectView.filterEditorView.getText()).toBe ''

        it "shows all files for the current project and selects the first", ->
          jasmine.attachToDOM(workspaceElement)

          dispatchCommand('toggle-file-finder')

          expect(projectView.find(".loading")).toBeVisible()
          expect(projectView.find(".loading").text().length).toBeGreaterThan 0

          waitForPathsToDisplay(projectView)

          runs ->
            eachFilePath [rootDir1, rootDir2], (filePath) ->
              item = projectView.list.find("li:contains(#{filePath})").eq(0)
              expect(item).toExist()
              nameDiv = item.find("div:first-child")
              expect(nameDiv).toHaveAttr("data-name", path.basename(filePath))
              expect(nameDiv).toHaveText(path.basename(filePath))

            expect(projectView.find(".loading")).not.toBeVisible()

        it "shows each file's path, including which root directory it's in", ->
          dispatchCommand('toggle-file-finder')

          waitForPathsToDisplay(projectView)

          runs ->
            eachFilePath [rootDir1], (filePath) ->
              item = projectView.list.find("li:contains(#{filePath})").eq(0)
              expect(item).toExist()
              expect(item.find("div").eq(1)).toHaveText(path.join(path.basename(rootDir1), filePath))

            eachFilePath [rootDir2], (filePath) ->
              item = projectView.list.find("li:contains(#{filePath})").eq(0)
              expect(item).toExist()
              expect(item.find("div").eq(1)).toHaveText(path.join(path.basename(rootDir2), filePath))

        it "only creates a single path loader task", ->
          spyOn(PathLoader, 'startTask').andCallThrough()
          dispatchCommand('toggle-file-finder') # Show
          dispatchCommand('toggle-file-finder') # Hide
          dispatchCommand('toggle-file-finder') # Show again
          expect(PathLoader.startTask.callCount).toBe 1

        it "puts the last active path first", ->
          waitsForPromise -> atom.workspace.open 'sample.txt'
          waitsForPromise -> atom.workspace.open 'sample.js'

          runs -> dispatchCommand('toggle-file-finder')

          waitForPathsToDisplay(projectView)

          runs ->
            expect(projectView.list.find("li:eq(0)").text()).toContain('sample.txt')
            expect(projectView.list.find("li:eq(1)").text()).toContain('sample.html')

        describe "symlinks on #darwin or #linux", ->
          [junkDirPath, junkFilePath] = []
          beforeEach ->
            junkDirPath = fs.realpathSync(temp.mkdirSync('junk-1'))
            junkFilePath = path.join(junkDirPath, 'file.txt')
            fs.writeFileSync(junkFilePath, 'txt')
            fs.writeFileSync(path.join(junkDirPath, 'a'), 'txt')

            brokenFilePath = path.join(junkDirPath, 'delete.txt')
            fs.writeFileSync(brokenFilePath, 'delete-me')

            fs.symlinkSync(junkFilePath, atom.project.getDirectories()[0].resolve('symlink-to-file'))
            fs.symlinkSync(junkDirPath, atom.project.getDirectories()[0].resolve('symlink-to-dir'))
            fs.symlinkSync(brokenFilePath, atom.project.getDirectories()[0].resolve('broken-symlink'))

            fs.symlinkSync(atom.project.getDirectories()[0].resolve('sample.txt'), atom.project.getDirectories()[0].resolve('symlink-to-internal-file'))
            fs.symlinkSync(atom.project.getDirectories()[0].resolve('dir'), atom.project.getDirectories()[0].resolve('symlink-to-internal-dir'))

            fs.unlinkSync(brokenFilePath)

          it "includes symlinked file paths", ->
            dispatchCommand('toggle-file-finder')

            waitForPathsToDisplay(projectView)

            runs ->
              expect(projectView.list.find("li:contains(symlink-to-file)")).toExist()
              expect(projectView.list.find("li:contains(symlink-to-internal-file)")).not.toExist()

          it "excludes symlinked folder paths if followSymlinks is false", ->
            atom.config.set('core.followSymlinks', false)

            dispatchCommand('toggle-file-finder')

            waitForPathsToDisplay(projectView)

            runs ->
              expect(projectView.list.find("li:contains(symlink-to-dir)")).not.toExist()
              expect(projectView.list.find("li:contains(symlink-to-dir/a)")).not.toExist()

              expect(projectView.list.find("li:contains(symlink-to-internal-dir)")).not.toExist()
              expect(projectView.list.find("li:contains(symlink-to-internal-dir/a)")).not.toExist()

          it "includes symlinked folder paths if followSymlinks is true", ->
            atom.config.set('core.followSymlinks', true)

            dispatchCommand('toggle-file-finder')

            waitForPathsToDisplay(projectView)

            runs ->
              expect(projectView.list.find("li:contains(symlink-to-dir/a)")).toExist()
              expect(projectView.list.find("li:contains(symlink-to-internal-dir/a)")).not.toExist()

        describe "socket files on #darwin or #linux", ->
          [socketServer, socketPath] = []

          beforeEach ->
            socketServer = net.createServer ->
            socketPath = path.join(rootDir1, "some.sock")
            waitsFor (done) -> socketServer.listen(socketPath, done)

          afterEach ->
            waitsFor (done) -> socketServer.close(done)

          it "ignores them", ->
            dispatchCommand('toggle-file-finder')
            waitForPathsToDisplay(projectView)
            expect(projectView.list.find("li:contains(some.sock)")).not.toExist()

        it "ignores paths that match entries in config.fuzzy-finder.ignoredNames", ->
          atom.config.set("fuzzy-finder.ignoredNames", ["sample.js", "*.txt"])

          dispatchCommand('toggle-file-finder')

          waitForPathsToDisplay(projectView)

          runs ->
            expect(projectView.list.find("li:contains(sample.js)")).not.toExist()
            expect(projectView.list.find("li:contains(sample.txt)")).not.toExist()
            expect(projectView.list.find("li:contains(a)")).toExist()

        it "only shows a given path once, even if it's within multiple root folders", ->
          childDir1 = path.join(rootDir1, 'a-child')
          childFile1 = path.join(childDir1, 'child-file.txt')
          fs.mkdirSync(childDir1)
          fs.writeFileSync(childFile1, 'stuff')
          atom.project.addPath(childDir1)

          dispatchCommand('toggle-file-finder')
          waitForPathsToDisplay(projectView)

          runs ->
            expect(projectView.list.find("li:contains(child-file.txt)").length).toBe 1

      describe "when the project only has one path", ->
        beforeEach ->
          atom.project.setPaths([rootDir1])

        it "doesn't show the name of each file's root directory", ->
          dispatchCommand('toggle-file-finder')

          waitForPathsToDisplay(projectView)

          runs ->
            eachFilePath [rootDir1], (filePath) ->
              item = projectView.list.find("li:contains(#{filePath})").eq(0)
              expect(item).toExist()
              expect(item).not.toHaveText(path.basename(rootDir1))

      describe "when the project has no path", ->
        beforeEach ->
          atom.project.setPaths([])

        it "shows an empty message with no files in the list", ->
          dispatchCommand('toggle-file-finder')
          expect(projectView.error.text()).toBe 'Project is empty'
          expect(projectView.list.children('li').length).toBe 0

    describe "when a path selection is confirmed", ->
      it "opens the file associated with that path in that split", ->
        jasmine.attachToDOM(workspaceElement)
        editor1 = atom.workspace.getActiveTextEditor()
        atom.workspace.getActivePane().splitRight(copyActiveItem: true)
        editor2 = atom.workspace.getActiveTextEditor()

        dispatchCommand('toggle-file-finder')

        expectedPath = atom.project.getDirectories()[0].resolve('dir/a')
        projectView.confirmed({filePath: expectedPath})

        waitsFor ->
          atom.workspace.getActivePane().getItems().length is 2

        runs ->
          editor3 = atom.workspace.getActiveTextEditor()
          expect(atom.workspace.panelForItem(projectView).isVisible()).toBe false
          expect(editor1.getPath()).not.toBe expectedPath
          expect(editor2.getPath()).not.toBe expectedPath
          expect(editor3.getPath()).toBe expectedPath
          expect(atom.views.getView(editor3)).toHaveFocus()

      describe "when the selected path is a directory", ->
        it "leaves the the tree view open, doesn't open the path in the editor, and displays an error", ->
          jasmine.attachToDOM(workspaceElement)
          editorPath = atom.workspace.getActiveTextEditor().getPath()
          dispatchCommand('toggle-file-finder')
          projectView.confirmed({filePath: atom.project.getDirectories()[0].resolve('dir')})
          expect(projectView.hasParent()).toBeTruthy()
          expect(atom.workspace.getActiveTextEditor().getPath()).toBe editorPath
          expect(projectView.error.text().length).toBeGreaterThan 0
          advanceClock(2000)
          expect(projectView.error.text().length).toBe 0

  describe "buffer-finder behavior", ->
    describe "toggling", ->
      describe "when there are pane items with paths", ->
        beforeEach ->
          jasmine.attachToDOM(workspaceElement)

          waitsForPromise ->
            atom.workspace.open('sample.txt')

        it "shows the FuzzyFinder if it isn't showing, or hides it and returns focus to the active editor", ->
          expect(atom.workspace.panelForItem(bufferView)).toBeNull()
          atom.workspace.getActivePane().splitRight(copyActiveItem: true)
          [editor1, editor2, editor3] = atom.workspace.getTextEditors()
          expect(atom.workspace.getActivePaneItem()).toBe editor3

          expect(atom.views.getView(editor3)).toHaveFocus()

          dispatchCommand('toggle-buffer-finder')
          expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe true
          expect(workspaceElement.querySelector('.fuzzy-finder')).toHaveFocus()
          bufferView.filterEditorView.getModel().insertText('this should not show up next time we toggle')

          dispatchCommand('toggle-buffer-finder')
          expect(atom.views.getView(editor3)).toHaveFocus()
          expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe false

          dispatchCommand('toggle-buffer-finder')
          expect(bufferView.filterEditorView.getText()).toBe ''

        it "lists the paths of the current items, sorted by most recently opened but with the current item last", ->
          waitsForPromise ->
            atom.workspace.open 'sample-with-tabs.coffee'

          runs ->
            dispatchCommand('toggle-buffer-finder')
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe true
            expect(_.pluck(bufferView.list.find('li > div.file'), 'outerText')).toEqual ['sample.txt', 'sample.js', 'sample-with-tabs.coffee']
            dispatchCommand('toggle-buffer-finder')
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe false

          waitsForPromise ->
            atom.workspace.open 'sample.txt'

          runs ->
            dispatchCommand('toggle-buffer-finder')
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe true
            expect(_.pluck(bufferView.list.find('li > div.file'), 'outerText')).toEqual ['sample-with-tabs.coffee', 'sample.js', 'sample.txt']
            expect(bufferView.list.children().first()).toHaveClass 'selected'

        it "serializes the list of paths and their last opened time", ->
          waitsForPromise ->
            atom.workspace.open 'sample-with-tabs.coffee'

          runs ->
            dispatchCommand('toggle-buffer-finder')

          waitsForPromise ->
            atom.workspace.open 'sample.js'

          runs ->
            dispatchCommand('toggle-buffer-finder')

          waitsForPromise ->
            atom.workspace.open()

          runs ->
            atom.packages.deactivatePackage('fuzzy-finder')
            states = _.map atom.packages.getPackageState('fuzzy-finder'), (path, time) -> [ path, time ]
            expect(states.length).toBe 3
            states = _.sortBy states, (path, time) -> -time

            paths = [ 'sample-with-tabs.coffee', 'sample.txt', 'sample.js' ]

            for [time, bufferPath] in states
              expect(_.last bufferPath.split path.sep).toBe paths.shift()
              expect(time).toBeGreaterThan 50000

      describe "when there are only panes with anonymous items", ->
        it "does not open", ->
          atom.workspace.getActivePane().destroy()
          waitsForPromise ->
            atom.workspace.open()

          runs ->
            dispatchCommand('toggle-buffer-finder')
            expect(atom.workspace.panelForItem(bufferView)).toBeNull()

      describe "when there are no pane items", ->
        it "does not open", ->
          atom.workspace.getActivePane().destroy()
          dispatchCommand('toggle-buffer-finder')
          expect(atom.workspace.panelForItem(bufferView)).toBeNull()

      describe "when multiple sessions are opened on the same path", ->
        it "does not display duplicates for that path in the list", ->
          waitsForPromise ->
            atom.workspace.open 'sample.js'

          runs ->
            atom.workspace.getActivePane().splitRight(copyActiveItem: true)
            dispatchCommand('toggle-buffer-finder')
            expect(_.pluck(bufferView.list.find('li > div.file'), 'outerText')).toEqual ['sample.js']

    describe "when a path selection is confirmed", ->
      [editor1, editor2, editor3] = []

      beforeEach ->
        jasmine.attachToDOM(workspaceElement)
        atom.workspace.getActivePane().splitRight(copyActiveItem: true)

        waitsForPromise ->
          atom.workspace.open('sample.txt')

        runs ->
          [editor1, editor2, editor3] = atom.workspace.getTextEditors()

          expect(atom.workspace.getActiveTextEditor()).toBe editor3

          atom.commands.dispatch atom.views.getView(editor2), 'pane:show-previous-item'
          dispatchCommand('toggle-buffer-finder')

      describe "when the active pane has an item for the selected path", ->
        it "switches to the item for the selected path", ->
          expectedPath = atom.project.getDirectories()[0].resolve('sample.txt')
          bufferView.confirmed({filePath: expectedPath})

          waitsFor ->
            atom.workspace.getActiveTextEditor().getPath() is expectedPath

          runs ->
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe false
            expect(editor1.getPath()).not.toBe expectedPath
            expect(editor2.getPath()).not.toBe expectedPath
            expect(editor3.getPath()).toBe expectedPath
            expect(atom.views.getView(editor3)).toHaveFocus()

      describe "when the active pane does not have an item for the selected path and fuzzy-finder.searchAllPanes is false", ->
        it "adds a new item to the active pane for the selected path", ->
          dispatchCommand('toggle-buffer-finder')

          atom.views.getView(editor1).focus()

          dispatchCommand('toggle-buffer-finder')

          expect(atom.workspace.getActiveTextEditor()).toBe editor1

          expectedPath = atom.project.getDirectories()[0].resolve('sample.txt')
          bufferView.confirmed({filePath: expectedPath}, atom.config.get 'fuzzy-finder.searchAllPanes')

          waitsFor ->
            atom.workspace.getActivePane().getItems().length is 2

          runs ->
            editor4 = atom.workspace.getActiveTextEditor()

            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe false

            expect(editor4).not.toBe editor1
            expect(editor4).not.toBe editor2
            expect(editor4).not.toBe editor3

            expect(editor4.getPath()).toBe expectedPath
            expect(atom.views.getView(editor4)).toHaveFocus()

      describe "when the active pane does not have an item for the selected path and fuzzy-finder.searchAllPanes is true", ->
        beforeEach ->
          atom.config.set("fuzzy-finder.searchAllPanes", true)

        it "switches to the pane with the item for the selected path", ->
          dispatchCommand('toggle-buffer-finder')

          atom.views.getView(editor1).focus()

          dispatchCommand('toggle-buffer-finder')

          expect(atom.workspace.getActiveTextEditor()).toBe editor1

          originalPane = atom.workspace.getActivePane()

          expectedPath = atom.project.getDirectories()[0].resolve('sample.txt')
          bufferView.confirmed({filePath: expectedPath}, searchAllPanes: atom.config.get('fuzzy-finder.searchAllPanes'))

          waitsFor ->
            atom.workspace.getActiveTextEditor().getPath() is expectedPath

          runs ->
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe false
            expect(atom.workspace.getActivePane()).not.toBe originalPane
            expect(atom.workspace.getActiveTextEditor()).toBe editor3
            expect(atom.workspace.getPaneItems().length).toBe 3

  describe "common behavior between file and buffer finder", ->
    describe "when the fuzzy finder is cancelled", ->
      describe "when an editor is open", ->
        it "detaches the finder and focuses the previously focused element", ->
          jasmine.attachToDOM(workspaceElement)
          activeEditor = atom.workspace.getActiveTextEditor()

          dispatchCommand('toggle-file-finder')
          expect(projectView.hasParent()).toBeTruthy()
          expect(projectView.filterEditorView).toHaveFocus()

          projectView.cancel()

          expect(atom.workspace.panelForItem(projectView).isVisible()).toBe false
          expect(atom.views.getView(activeEditor)).toHaveFocus()

      describe "when no editors are open", ->
        it "detaches the finder and focuses the previously focused element", ->
          jasmine.attachToDOM(workspaceElement)
          atom.workspace.getActivePane().destroy()

          inputView = $$ -> @input()
          workspaceElement.appendChild(inputView[0])
          inputView.focus()

          dispatchCommand('toggle-file-finder')
          expect(projectView.hasParent()).toBeTruthy()
          expect(projectView.filterEditorView).toHaveFocus()

          projectView.cancel()

          expect(atom.workspace.panelForItem(projectView).isVisible()).toBe false
          expect(inputView).toHaveFocus()

  describe "cached file paths", ->
    beforeEach ->
      spyOn(PathLoader, "startTask").andCallThrough()
      spyOn(atom.workspace, "getTextEditors").andCallThrough()

    it "caches file paths after first time", ->
      dispatchCommand('toggle-file-finder')

      waitForPathsToDisplay(projectView)

      runs ->
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
        dispatchCommand('toggle-file-finder')
        dispatchCommand('toggle-file-finder')

      waitForPathsToDisplay(projectView)

      runs ->
        expect(PathLoader.startTask).not.toHaveBeenCalled()

    it "doesn't cache buffer paths", ->
      dispatchCommand('toggle-buffer-finder')

      waitForPathsToDisplay(bufferView)

      runs ->
        expect(atom.workspace.getTextEditors).toHaveBeenCalled()
        atom.workspace.getTextEditors.reset()
        dispatchCommand('toggle-buffer-finder')
        dispatchCommand('toggle-buffer-finder')

      waitForPathsToDisplay(bufferView)

      runs ->
        expect(atom.workspace.getTextEditors).toHaveBeenCalled()

    it "busts the cache when the window gains focus", ->
      dispatchCommand('toggle-file-finder')

      waitForPathsToDisplay(projectView)

      runs ->
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
        window.dispatchEvent new CustomEvent('focus')
        dispatchCommand('toggle-file-finder')
        dispatchCommand('toggle-file-finder')
        expect(PathLoader.startTask).toHaveBeenCalled()

    it "busts the cache when the project path changes", ->
      dispatchCommand('toggle-file-finder')

      waitForPathsToDisplay(projectView)

      runs ->
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
        atom.project.setPaths([temp.mkdirSync('atom')])
        dispatchCommand('toggle-file-finder')
        dispatchCommand('toggle-file-finder')
        expect(PathLoader.startTask).toHaveBeenCalled()
        expect(projectView.list.children('li').length).toBe 0

    describe "the initial load paths task started during package activation", ->
      beforeEach ->
        fuzzyFinder.projectView.destroy()
        fuzzyFinder.projectView = null
        fuzzyFinder.startLoadPathsTask()

        waitsFor ->
          fuzzyFinder.projectPaths

      it "passes the indexed paths into the project view when it is created", ->
        {projectPaths} = fuzzyFinder
        expect(projectPaths.length).toBe 18
        projectView = fuzzyFinder.createProjectView()
        expect(projectView.paths).toBe projectPaths
        expect(projectView.reloadPaths).toBe false

      it "busts the cached paths when the project paths change", ->
        atom.project.setPaths([])

        {projectPaths} = fuzzyFinder
        expect(projectPaths).toBe null

        projectView = fuzzyFinder.createProjectView()
        expect(projectView.paths).toBe null
        expect(projectView.reloadPaths).toBe true

  describe "opening a path into a split", ->
    it "opens the path by splitting the active editor left", ->
      expect(atom.workspace.getPanes().length).toBe 1
      pane = atom.workspace.getActivePane()

      dispatchCommand('toggle-buffer-finder')
      {filePath} = bufferView.getSelectedItem()
      atom.commands.dispatch bufferView.filterEditorView.element, 'pane:split-left'

      waitsFor ->
        atom.workspace.getPanes().length is 2

      waitsFor ->
        atom.workspace.getActiveTextEditor()

      runs ->
        [leftPane, rightPane] = atom.workspace.getPanes()
        expect(atom.workspace.getActivePane()).toBe leftPane
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe atom.project.getDirectories()[0].resolve(filePath)

    it "opens the path by splitting the active editor right", ->
      expect(atom.workspace.getPanes().length).toBe 1
      pane = atom.workspace.getActivePane()

      dispatchCommand('toggle-buffer-finder')
      {filePath} = bufferView.getSelectedItem()
      atom.commands.dispatch bufferView.filterEditorView.element, 'pane:split-right'

      waitsFor ->
        atom.workspace.getPanes().length is 2

      waitsFor ->
        atom.workspace.getActiveTextEditor()

      runs ->
        [leftPane, rightPane] = atom.workspace.getPanes()
        expect(atom.workspace.getActivePane()).toBe rightPane
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe atom.project.getDirectories()[0].resolve(filePath)

    it "opens the path by splitting the active editor up", ->
      expect(atom.workspace.getPanes().length).toBe 1
      pane = atom.workspace.getActivePane()

      dispatchCommand('toggle-buffer-finder')
      {filePath} = bufferView.getSelectedItem()
      atom.commands.dispatch bufferView.filterEditorView.element, 'pane:split-up'

      waitsFor ->
        atom.workspace.getPanes().length is 2

      waitsFor ->
        atom.workspace.getActiveTextEditor()

      runs ->
        [topPane, bottomPane] = atom.workspace.getPanes()
        expect(atom.workspace.getActivePane()).toBe topPane
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe atom.project.getDirectories()[0].resolve(filePath)

    it "opens the path by splitting the active editor down", ->
      expect(atom.workspace.getPanes().length).toBe 1
      pane = atom.workspace.getActivePane()

      dispatchCommand('toggle-buffer-finder')
      {filePath} = bufferView.getSelectedItem()
      atom.commands.dispatch bufferView.filterEditorView.element, 'pane:split-down'

      waitsFor ->
        atom.workspace.getPanes().length is 2

      waitsFor ->
        atom.workspace.getActiveTextEditor()

      runs ->
        [topPane, bottomPane] = atom.workspace.getPanes()
        expect(atom.workspace.getActivePane()).toBe bottomPane
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe atom.project.getDirectories()[0].resolve(filePath)

  describe "when the filter text contains a colon followed by a number", ->
    beforeEach ->
      jasmine.attachToDOM(workspaceElement)
      expect(atom.workspace.panelForItem(projectView)).toBeNull()

      waitsForPromise ->
        atom.workspace.open('sample.txt')

      runs ->
        [editor1, editor2] = atom.workspace.getTextEditors()
        expect(atom.workspace.getActiveTextEditor()).toBe editor2
        expect(editor1.getCursorBufferPosition()).toEqual [0, 0]

    describe "when the filter text has a file path", ->
      it "opens the selected path to that line number", ->
        [editor1, editor2] = atom.workspace.getTextEditors()

        dispatchCommand('toggle-buffer-finder')
        expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe true

        bufferView.filterEditorView.getModel().setText('sample.js:4')
        bufferView.populateList()
        {filePath} = bufferView.getSelectedItem()
        expect(atom.project.getDirectories()[0].resolve(filePath)).toBe editor1.getPath()

        spyOn(bufferView, 'moveToLine').andCallThrough()
        atom.commands.dispatch bufferView.element, 'core:confirm'

        waitsFor ->
          bufferView.moveToLine.callCount > 0

        runs ->
          expect(atom.workspace.getActiveTextEditor()).toBe editor1
          expect(editor1.getCursorBufferPosition()).toEqual [3, 4]

  describe "match highlighting", ->
    beforeEach ->
      jasmine.attachToDOM(workspaceElement)
      dispatchCommand('toggle-buffer-finder')

    it "highlights an exact match", ->
      bufferView.filterEditorView.getModel().setText('sample.js')
      bufferView.populateList()
      resultView = bufferView.getSelectedItemView()

      primaryMatches = resultView.find('.primary-line .character-match')
      secondaryMatches = resultView.find('.secondary-line .character-match')
      expect(primaryMatches.length).toBe 1
      expect(primaryMatches.last().text()).toBe 'sample.js'
      # Use `toBeGreaterThan` because dir may have some characters in it
      expect(secondaryMatches.length).toBeGreaterThan 0
      expect(secondaryMatches.last().text()).toBe 'sample.js'

    it "highlights a partial match", ->
      bufferView.filterEditorView.getModel().setText('sample')
      bufferView.populateList()
      resultView = bufferView.getSelectedItemView()

      primaryMatches = resultView.find('.primary-line .character-match')
      secondaryMatches = resultView.find('.secondary-line .character-match')
      expect(primaryMatches.length).toBe 1
      expect(primaryMatches.last().text()).toBe 'sample'
      # Use `toBeGreaterThan` because dir may have some characters in it
      expect(secondaryMatches.length).toBeGreaterThan 0
      expect(secondaryMatches.last().text()).toBe 'sample'

    it "highlights multiple matches in the file name", ->
      bufferView.filterEditorView.getModel().setText('samplejs')
      bufferView.populateList()
      resultView = bufferView.getSelectedItemView()

      primaryMatches = resultView.find('.primary-line .character-match')
      secondaryMatches = resultView.find('.secondary-line .character-match')
      expect(primaryMatches.length).toBe 2
      expect(primaryMatches.first().text()).toBe 'sample'
      expect(primaryMatches.last().text()).toBe 'js'
      # Use `toBeGreaterThan` because dir may have some characters in it
      expect(secondaryMatches.length).toBeGreaterThan 1
      expect(secondaryMatches.last().text()).toBe 'js'

    it "highlights matches in the directory and file name", ->
      bufferView.items = [
        {
          filePath: '/test/root-dir1/sample.js'
          projectRelativePath: 'root-dir1/sample.js'
        }
      ]
      bufferView.filterEditorView.getModel().setText('root-dirsample')
      bufferView.populateList()
      resultView = bufferView.getSelectedItemView()

      primaryMatches = resultView.find('.primary-line .character-match')
      expect(primaryMatches.length).toBe 1
      expect(primaryMatches.last().text()).toBe 'sample'

      secondaryMatches = resultView.find('.secondary-line .character-match')
      expect(secondaryMatches.length).toBe 2
      expect(secondaryMatches.first().text()).toBe 'root-dir'
      expect(secondaryMatches.last().text()).toBe 'sample'

    describe "when the filter text doesn't have a file path", ->
      it "moves the cursor in the active editor to that line number", ->
        [editor1, editor2] = atom.workspace.getTextEditors()

        waitsForPromise ->
          atom.workspace.open('sample.js')

        runs ->
          expect(atom.workspace.getActiveTextEditor()).toBe editor1

          dispatchCommand('toggle-buffer-finder')
          expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe true

          bufferView.filterEditorView.getModel().insertText(':4')
          bufferView.populateList()
          expect(bufferView.list.children('li').length).toBe 0

          spyOn(bufferView, 'moveToLine').andCallThrough()
          atom.commands.dispatch bufferView.element, 'core:confirm'

        waitsFor ->
          bufferView.moveToLine.callCount > 0

        runs ->
          expect(atom.workspace.getActiveTextEditor()).toBe editor1
          expect(editor1.getCursorBufferPosition()).toEqual [3, 4]

    describe "when splitting panes", ->
      it "opens the selected path to that line number in a new pane", ->
        [editor1, editor2] = atom.workspace.getTextEditors()

        waitsForPromise ->
          atom.workspace.open('sample.js')

        runs ->
          expect(atom.workspace.getActiveTextEditor()).toBe editor1

          dispatchCommand('toggle-buffer-finder')
          expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe true

          bufferView.filterEditorView.getModel().insertText(':4')
          bufferView.populateList()
          expect(bufferView.list.children('li').length).toBe 0

          spyOn(bufferView, 'moveToLine').andCallThrough()
          atom.commands.dispatch bufferView.filterEditorView.element, 'pane:split-left'

        waitsFor ->
          bufferView.moveToLine.callCount > 0

        runs ->
          expect(atom.workspace.getActiveTextEditor()).not.toBe editor1
          expect(atom.workspace.getActiveTextEditor().getPath()).toBe editor1.getPath()
          expect(atom.workspace.getActiveTextEditor().getCursorBufferPosition()).toEqual [3, 4]

  describe "preserve last search", ->
    it "does not preserve last search by default", ->
      dispatchCommand('toggle-file-finder')
      expect(atom.workspace.panelForItem(projectView).isVisible()).toBe true
      projectView.filterEditorView.getModel().insertText('this should not show up next time we open finder')

      dispatchCommand('toggle-file-finder')
      expect(atom.workspace.panelForItem(projectView).isVisible()).toBe false

      dispatchCommand('toggle-file-finder')
      expect(atom.workspace.panelForItem(projectView).isVisible()).toBe true
      expect(projectView.filterEditorView.getText()).toBe ''

    it "preserves last search when the config is set", ->
      atom.config.set("fuzzy-finder.preserveLastSearch", true)

      dispatchCommand('toggle-file-finder')
      expect(atom.workspace.panelForItem(projectView).isVisible()).toBe true
      projectView.filterEditorView.getModel().insertText('this should show up next time we open finder')

      dispatchCommand('toggle-file-finder')
      expect(atom.workspace.panelForItem(projectView).isVisible()).toBe false

      dispatchCommand('toggle-file-finder')
      expect(atom.workspace.panelForItem(projectView).isVisible()).toBe true
      expect(projectView.filterEditorView.getText()).toBe 'this should show up next time we open finder'
      expect(projectView.filterEditorView.getModel().getSelectedText()).toBe 'this should show up next time we open finder'

  describe "Git integration", ->
    [projectPath, gitRepository, gitDirectory] = []

    beforeEach ->
      projectPath = atom.project.getDirectories()[0].resolve('git/working-dir')
      fs.moveSync(path.join(projectPath, 'git.git'), path.join(projectPath, '.git'))
      atom.project.setPaths([rootDir2, projectPath])

      gitDirectory = atom.project.getDirectories()[1]
      gitRepository = atom.project.getRepositories()[1]

    describe "git-status-finder behavior", ->
      [originalText, originalPath, newPath] = []

      beforeEach ->
        waitsForPromise ->
          atom.workspace.open(path.join(projectPath, 'a.txt'))

        runs ->
          editor = atom.workspace.getActiveTextEditor()
          originalText = editor.getText()
          originalPath = editor.getPath()
          fs.writeFileSync(originalPath, 'making a change for the better')
          gitRepository.getPathStatus(originalPath)

          newPath = atom.project.getDirectories()[1].resolve('newsample.js')
          fs.writeFileSync(newPath, '')
          gitRepository.getPathStatus(newPath)

      it "displays all new and modified paths", ->
        expect(atom.workspace.panelForItem(gitStatusView)).toBeNull()
        dispatchCommand('toggle-git-status-finder')
        expect(atom.workspace.panelForItem(gitStatusView).isVisible()).toBe true

        expect(gitStatusView.find('.file').length).toBe 2

        expect(gitStatusView.find('.status.status-modified').length).toBe 1
        expect(gitStatusView.find('.status.status-added').length).toBe 1

    describe "status decorations", ->
      [originalText, originalPath, editor, newPath] = []

      beforeEach ->
        jasmine.attachToDOM(workspaceElement)

        waitsForPromise ->
          atom.workspace.open(path.join(projectPath, 'a.txt'))

        runs ->
          editor = atom.workspace.getActiveTextEditor()
          originalText = editor.getText()
          originalPath = editor.getPath()
          newPath = gitDirectory.resolve('newsample.js')
          fs.writeFileSync(newPath, '')

      describe "when a modified file is shown in the list", ->
        it "displays the modified icon", ->
          editor.setText('modified')
          editor.save()
          gitRepository.getPathStatus(editor.getPath())

          dispatchCommand('toggle-buffer-finder')
          expect(bufferView.find('.status.status-modified').length).toBe 1
          expect(bufferView.find('.status.status-modified').closest('li').find('.file').text()).toBe 'a.txt'

      describe "when a new file is shown in the list", ->
        it "displays the new icon", ->
          waitsForPromise ->
            atom.workspace.open(path.join(projectPath, 'newsample.js'))

          runs ->
            gitRepository.getPathStatus(editor.getPath())

            dispatchCommand('toggle-buffer-finder')
            expect(bufferView.find('.status.status-added').length).toBe 1
            expect(bufferView.find('.status.status-added').closest('li').find('.file').text()).toBe 'newsample.js'

    describe "when core.excludeVcsIgnoredPaths is set to true", ->
      beforeEach ->
        atom.config.set("core.excludeVcsIgnoredPaths", true)

      describe "when the project's path is the repository's working directory", ->
        beforeEach ->
          ignoreFile = path.join(projectPath, '.gitignore')
          fs.writeFileSync(ignoreFile, 'ignored.txt')

          ignoredFile = path.join(projectPath, 'ignored.txt')
          fs.writeFileSync(ignoredFile, 'ignored text')

        it "excludes paths that are git ignored", ->
          dispatchCommand('toggle-file-finder')
          projectView.setMaxItems(Infinity)

          waitForPathsToDisplay(projectView)

          runs ->
            expect(projectView.list.find("li:contains(ignored.txt)")).not.toExist()

      describe "when the project's path is a subfolder of the repository's working directory", ->
        beforeEach ->
          atom.project.setPaths([gitDirectory.resolve('dir')])
          ignoreFile = path.join(projectPath, '.gitignore')
          fs.writeFileSync(ignoreFile, 'b.txt')

        it "does not exclude paths that are git ignored", ->
          dispatchCommand('toggle-file-finder')
          projectView.setMaxItems(Infinity)

          waitForPathsToDisplay(projectView)

          runs ->
            expect(projectView.list.find("li:contains(b.txt)")).toExist()

      describe "when the .gitignore matches parts of the path to the root folder", ->
        beforeEach ->
          ignoreFile = path.join(projectPath, '.gitignore')
          fs.writeFileSync(ignoreFile, path.basename(projectPath))

        it "only applies the .gitignore patterns to relative paths within the root folder", ->
          dispatchCommand('toggle-file-finder')
          projectView.setMaxItems(Infinity)

          waitForPathsToDisplay(projectView)

          runs ->
            expect(projectView.list.find("li:contains(file.txt)")).toExist()
