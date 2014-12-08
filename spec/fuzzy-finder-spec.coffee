path = require 'path'

_ = require 'underscore-plus'
{$, $$} = require 'atom-space-pen-views'
fs = require 'fs-plus'
temp = require 'temp'
wrench = require 'wrench'

PathLoader = require '../lib/path-loader'

describe 'FuzzyFinder', ->
  [projectView, bufferView, gitStatusView, workspaceElement] = []

  beforeEach ->
    tempPath = fs.realpathSync(temp.mkdirSync('atom'))
    fixturesPath = atom.project.getPaths()[0]
    wrench.copyDirSyncRecursive(fixturesPath, tempPath, forceDelete: true)
    atom.project.setPaths([path.join(tempPath, 'fuzzy-finder')])

    workspaceElement = atom.views.getView(atom.workspace)

    waitsForPromise ->
      atom.workspace.open('sample.js')

    waitsForPromise ->
      atom.packages.activatePackage('fuzzy-finder').then (pack) ->
        fuzzyFinder = pack.mainModule
        projectView = fuzzyFinder.createProjectView()
        bufferView = fuzzyFinder.createBufferView()
        gitStatusView = fuzzyFinder.createGitStatusView()

  describe "file-finder behavior", ->
    describe "toggling", ->
      describe "when the root view's project has a path", ->
        it "shows the FuzzyFinder or hides it and returns focus to the active editor if it already showing", ->
          jasmine.attachToDOM(workspaceElement)

          expect(atom.workspace.panelForItem(projectView)).toBeNull()
          atom.workspace.getActivePane().splitRight(copyActiveItem: true)
          [editor1, editor2] = atom.workspace.getTextEditors()

          expect(atom.workspace.panelForItem(projectView)).toBeNull()
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
          expect(atom.workspace.panelForItem(projectView).isVisible()).toBe true
          expect(projectView.filterEditorView).toHaveFocus()
          projectView.filterEditorView.getModel().insertText('this should not show up next time we toggle')

          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
          expect(atom.views.getView(editor1)).not.toHaveFocus()
          expect(atom.views.getView(editor2)).toHaveFocus()
          expect(atom.workspace.panelForItem(projectView).isVisible()).toBe false

          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
          expect(projectView.filterEditorView.getText()).toBe ''

        it "shows all relative file paths for the current project and selects the first", ->
          jasmine.attachToDOM(workspaceElement)
          projectView.setMaxItems(Infinity)
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
          paths = null
          expect(projectView.find(".loading")).toBeVisible()
          expect(projectView.find(".loading").text().length).toBeGreaterThan 0

          waitsFor "all project paths to load", 5000, ->
            {paths} = projectView
            paths?.length > 0

          runs ->
            expect(paths.length).toBeGreaterThan 0
            expect(projectView.list.children('li').length).toBe paths.length
            for filePath in paths
              expect(projectView.list.find("li:contains(#{path.basename(filePath)})")).toExist()
            firstChild = projectView.list.children().first()
            firstChildName = firstChild.find('div:first-child')
            firstChildPath = firstChild.find('div:last-child')

            expect(firstChild).toHaveClass 'selected'
            expect(firstChildName).toHaveAttr('data-name', firstChildName.text())
            expect(firstChildName).toHaveAttr('data-path', firstChildPath.text())
            expect(projectView.find(".loading")).not.toBeVisible()

        it "only creates a single path loader task", ->
          jasmine.attachToDOM(workspaceElement)
          spyOn(PathLoader, 'startTask').andCallThrough()
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder' # Show
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder' # Hide
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder' # Show again
          expect(PathLoader.startTask.callCount).toBe 1

        it "puts the last active path first", ->
          jasmine.attachToDOM(workspaceElement)

          waitsForPromise ->
            atom.workspace.open 'sample.txt'

          waitsForPromise ->
            atom.workspace.open 'sample.js'

          runs ->
            projectView.setMaxItems(Infinity)
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'

          waitsFor "all project paths to load", 5000, ->
            projectView.paths?.length > 0

          runs ->
            expect(projectView.list.find("li:eq(0)").text()).toContain('sample.txt')
            expect(projectView.list.find("li:eq(1)").text()).toContain('sample.js')

        describe "symlinks on #darwin or #linux", ->
          beforeEach ->
            fs.symlinkSync(atom.project.resolve('sample.txt'), atom.project.resolve('symlink-to-file'))
            fs.symlinkSync(atom.project.resolve('dir'), atom.project.resolve('symlink-to-dir'))

          it "includes symlinked file paths", ->
            jasmine.attachToDOM(workspaceElement)
            projectView.setMaxItems(Infinity)
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'

            waitsFor "all project paths to load", 5000, ->
              projectView.paths?.length > 0

            runs ->
              expect(projectView.list.find("li:contains(symlink-to-file)")).toExist()

          it "excludes symlinked folder paths if traverseIntoSymlinkDirectories is false", ->
            atom.config.set('fuzzy-finder.traverseIntoSymlinkDirectories', false)

            jasmine.attachToDOM(workspaceElement)
            projectView.setMaxItems(Infinity)
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'

            waitsFor "all project paths to load", 5000, ->
              not projectView.reloadPaths

            runs ->
              expect(projectView.list.find("li:contains(symlink-to-dir)")).not.toExist()
              expect(projectView.list.find("li:contains(symlink-to-dir/a)")).not.toExist()

          it "includes symlinked folder paths if traverseIntoSymlinkDirectories is true", ->
            atom.config.set('fuzzy-finder.traverseIntoSymlinkDirectories', true)

            jasmine.attachToDOM(workspaceElement)
            projectView.setMaxItems(Infinity)
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'

            waitsFor "all project paths to load", 5000, ->
              projectView.paths?.length > 0

            runs ->
              expect(projectView.list.find("li:contains(symlink-to-dir/a)")).toExist()

      describe "when the project has no path", ->
        beforeEach ->
          atom.project.setPaths([])

        it "shows an empty message with no files in the list", ->
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
          expect(projectView.error.text()).toBe 'Project is empty'
          expect(projectView.list.children('li').length).toBe 0

    describe "when a path selection is confirmed", ->
      it "opens the file associated with that path in that split", ->
        jasmine.attachToDOM(workspaceElement)
        editor1 = atom.workspace.getActiveTextEditor()
        atom.workspace.getActivePane().splitRight(copyActiveItem: true)
        editor2 = atom.workspace.getActiveTextEditor()
        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'

        expectedPath = atom.project.resolve('dir/a')
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
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
          projectView.confirmed({filePath: atom.project.resolve('dir')})
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

          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
          expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe true
          expect(workspaceElement.querySelector('.fuzzy-finder')).toHaveFocus()
          bufferView.filterEditorView.getModel().insertText('this should not show up next time we toggle')

          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
          expect(atom.views.getView(editor3)).toHaveFocus()
          expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe false

          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
          expect(bufferView.filterEditorView.getText()).toBe ''

        it "lists the paths of the current items, sorted by most recently opened but with the current item last", ->
          waitsForPromise ->
            atom.workspace.open 'sample-with-tabs.coffee'

          runs ->
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe true
            expect(_.pluck(bufferView.list.find('li > div.file'), 'outerText')).toEqual ['sample.txt', 'sample.js', 'sample-with-tabs.coffee']
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe false

          waitsForPromise ->
            atom.workspace.open 'sample.txt'

          runs ->
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe true
            expect(_.pluck(bufferView.list.find('li > div.file'), 'outerText')).toEqual ['sample-with-tabs.coffee', 'sample.js', 'sample.txt']
            expect(bufferView.list.children().first()).toHaveClass 'selected'

        it "serializes the list of paths and their last opened time", ->
          waitsForPromise ->
            atom.workspace.open 'sample-with-tabs.coffee'

          runs ->
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'

          waitsForPromise ->
            atom.workspace.open 'sample.js'

          runs ->
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'

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
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
            expect(atom.workspace.panelForItem(bufferView)).toBeNull()

      describe "when there are no pane items", ->
        it "does not open", ->
          atom.workspace.getActivePane().destroy()
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
          expect(atom.workspace.panelForItem(bufferView)).toBeNull()

      describe "when multiple sessions are opened on the same path", ->
        it "does not display duplicates for that path in the list", ->
          waitsForPromise ->
            atom.workspace.open 'sample.js'

          runs ->
            atom.workspace.getActivePane().splitRight(copyActiveItem: true)
            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
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
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'

      describe "when the active pane has an item for the selected path", ->
        it "switches to the item for the selected path", ->
          expectedPath = atom.project.resolve('sample.txt')
          bufferView.confirmed({filePath: expectedPath})

          waitsFor ->
            atom.workspace.getActiveTextEditor().getPath() == expectedPath

          runs ->
            expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe false
            expect(editor1.getPath()).not.toBe expectedPath
            expect(editor2.getPath()).not.toBe expectedPath
            expect(editor3.getPath()).toBe expectedPath
            expect(atom.views.getView(editor3)).toHaveFocus()

      describe "when the active pane does not have an item for the selected path", ->
        it "adds a new item to the active pane for the selcted path", ->
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
          atom.views.getView(editor1).focus()
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'

          expect(atom.workspace.getActiveTextEditor()).toBe editor1

          expectedPath = atom.project.resolve('sample.txt')
          bufferView.confirmed({filePath: expectedPath})

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

  describe "common behavior between file and buffer finder", ->
    describe "when the fuzzy finder is cancelled", ->
      describe "when an editor is open", ->
        it "detaches the finder and focuses the previously focused element", ->
          jasmine.attachToDOM(workspaceElement)
          activeEditor = atom.workspace.getActiveTextEditor()

          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
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

          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
          expect(projectView.hasParent()).toBeTruthy()
          expect(projectView.filterEditorView).toHaveFocus()

          projectView.cancel()

          expect(atom.workspace.panelForItem(projectView).isVisible()).toBe false
          expect(inputView).toHaveFocus()

  describe "cached file paths", ->
    it "caches file paths after first time", ->
      spyOn(PathLoader, "startTask").andCallThrough()
      atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'

      waitsFor ->
        projectView.list.children('li').length > 0

      runs ->
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'

      waitsFor ->
        projectView.list.children('li').length > 0

      runs ->
        expect(PathLoader.startTask).not.toHaveBeenCalled()

    it "doesn't cache buffer paths", ->
      spyOn(atom.workspace, "getTextEditors").andCallThrough()
      atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'

      waitsFor ->
        bufferView.list.children('li').length > 0

      runs ->
        expect(atom.workspace.getTextEditors).toHaveBeenCalled()
        atom.workspace.getTextEditors.reset()
        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'

      waitsFor ->
        bufferView.list.children('li').length > 0

      runs ->
        expect(atom.workspace.getTextEditors).toHaveBeenCalled()

    it "busts the cache when the window gains focus", ->
      spyOn(PathLoader, "startTask").andCallThrough()
      atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'

      waitsFor ->
        projectView.list.children('li').length > 0

      runs ->
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
        window.dispatchEvent new CustomEvent('focus')
        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
        expect(PathLoader.startTask).toHaveBeenCalled()

    it "busts the cache when the project path changes", ->
      spyOn(PathLoader, "startTask").andCallThrough()
      atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'

      waitsFor ->
        projectView.list.children('li').length > 0

      runs ->
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
        atom.project.setPaths([temp.mkdirSync('atom')])
        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
        expect(PathLoader.startTask).toHaveBeenCalled()
        expect(projectView.list.children('li').length).toBe 0

  it "ignores paths that match entries in config.fuzzy-finder.ignoredNames", ->
    atom.config.set("fuzzy-finder.ignoredNames", ["sample.js", "*.txt"])
    atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
    projectView.setMaxItems(Infinity)

    waitsFor ->
      projectView.list.children('li').length > 0

    runs ->
      expect(projectView.list.find("li:contains(sample.js)")).not.toExist()
      expect(projectView.list.find("li:contains(sample.txt)")).not.toExist()
      expect(projectView.list.find("li:contains(a)")).toExist()

  describe "opening a path into a split", ->
    it "opens the path by splitting the active editor left", ->
      expect(atom.workspace.getPanes().length).toBe 1
      pane = atom.workspace.getActivePane()

      atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
      {filePath} = bufferView.getSelectedItem()
      atom.commands.dispatch bufferView.filterEditorView.element, 'pane:split-left'

      waitsFor ->
        atom.workspace.getPanes().length is 2

      runs ->
        [leftPane, rightPane] = atom.workspace.getPanes()
        expect(atom.workspace.getActivePane()).toBe leftPane
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe atom.project.resolve(filePath)

    it "opens the path by splitting the active editor right", ->
      expect(atom.workspace.getPanes().length).toBe 1
      pane = atom.workspace.getActivePane()

      atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
      {filePath} = bufferView.getSelectedItem()
      atom.commands.dispatch bufferView.filterEditorView.element, 'pane:split-right'

      waitsFor ->
        atom.workspace.getPanes().length is 2

      runs ->
        [leftPane, rightPane] = atom.workspace.getPanes()
        expect(atom.workspace.getActivePane()).toBe rightPane
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe atom.project.resolve(filePath)

    it "opens the path by splitting the active editor up", ->
      expect(atom.workspace.getPanes().length).toBe 1
      pane = atom.workspace.getActivePane()

      atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
      {filePath} = bufferView.getSelectedItem()
      atom.commands.dispatch bufferView.filterEditorView.element, 'pane:split-up'

      waitsFor ->
        atom.workspace.getPanes().length is 2

      runs ->
        [topPane, bottomPane] = atom.workspace.getPanes()
        expect(atom.workspace.getActivePane()).toBe topPane
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe atom.project.resolve(filePath)

    it "opens the path by splitting the active editor down", ->
      expect(atom.workspace.getPanes().length).toBe 1
      pane = atom.workspace.getActivePane()

      atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
      {filePath} = bufferView.getSelectedItem()
      atom.commands.dispatch bufferView.filterEditorView.element, 'pane:split-down'

      waitsFor ->
        atom.workspace.getPanes().length is 2

      runs ->
        [topPane, bottomPane] = atom.workspace.getPanes()
        expect(atom.workspace.getActivePane()).toBe bottomPane
        expect(atom.workspace.getActiveTextEditor().getPath()).toBe atom.project.resolve(filePath)

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

        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
        expect(atom.workspace.panelForItem(bufferView).isVisible()).toBe true

        bufferView.filterEditorView.getModel().setText('sample.js:4')
        bufferView.populateList()
        {filePath} = bufferView.getSelectedItem()
        expect(atom.project.resolve(filePath)).toBe editor1.getPath()

        spyOn(bufferView, 'moveToLine').andCallThrough()
        atom.commands.dispatch bufferView.element, 'core:confirm'

        waitsFor ->
          bufferView.moveToLine.callCount > 0

        runs ->
          expect(atom.workspace.getActiveTextEditor()).toBe editor1
          expect(editor1.getCursorBufferPosition()).toEqual [3, 4]

    describe "when the filter text doesn't have a file path", ->
      it "moves the cursor in the active editor to that line number", ->
        [editor1, editor2] = atom.workspace.getTextEditors()

        waitsForPromise ->
          atom.workspace.open('sample.js')

        runs ->
          expect(atom.workspace.getActiveTextEditor()).toBe editor1

          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
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

          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
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

  describe "Git integration", ->
    [projectPath] = []

    beforeEach ->
      projectPath = atom.project.resolve('git/working-dir')
      fs.moveSync(path.join(projectPath, 'git.git'), path.join(projectPath, '.git'))
      atom.project.setPaths([projectPath])

    describe "git-status-finder behavior", ->
      [originalText, originalPath, newPath] = []

      beforeEach ->
        waitsForPromise ->
          atom.workspace.open('a.txt')

        runs ->
          editor = atom.workspace.getActiveTextEditor()
          originalText = editor.getText()
          originalPath = editor.getPath()
          fs.writeFileSync(originalPath, 'making a change for the better')
          atom.project.getRepositories()[0].getPathStatus(originalPath)

          newPath = atom.project.resolve('newsample.js')
          fs.writeFileSync(newPath, '')
          atom.project.getRepositories()[0].getPathStatus(newPath)

      it "displays all new and modified paths", ->
        expect(atom.workspace.panelForItem(gitStatusView)).toBeNull()
        atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-git-status-finder'
        expect(atom.workspace.panelForItem(gitStatusView).isVisible()).toBe true

        expect(gitStatusView.find('.file').length).toBe 2

        expect(gitStatusView.find('.status.status-modified').length).toBe 1
        expect(gitStatusView.find('.status.status-added').length).toBe 1

    describe "status decorations", ->
      [originalText, originalPath, editor, newPath] = []

      beforeEach ->
        jasmine.attachToDOM(workspaceElement)

        waitsForPromise ->
          atom.workspace.open('a.txt')

        runs ->
          editor = atom.workspace.getActiveTextEditor()
          originalText = editor.getText()
          originalPath = editor.getPath()
          newPath = atom.project.resolve('newsample.js')
          fs.writeFileSync(newPath, '')

      describe "when a modified file is shown in the list", ->
        it "displays the modified icon", ->
          editor.setText('modified')
          editor.save()
          atom.project.getRepositories()[0].getPathStatus(editor.getPath())

          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
          expect(bufferView.find('.status.status-modified').length).toBe 1
          expect(bufferView.find('.status.status-modified').closest('li').find('.file').text()).toBe 'a.txt'

      describe "when a new file is shown in the list", ->
        it "displays the new icon", ->
          waitsForPromise ->
            atom.workspace.open('newsample.js')

          runs ->
            atom.project.getRepositories()[0].getPathStatus(editor.getPath())

            atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-buffer-finder'
            expect(bufferView.find('.status.status-added').length).toBe 1
            expect(bufferView.find('.status.status-added').closest('li').find('.file').text()).toBe 'newsample.js'

    describe "when core.excludeVcsIgnoredPaths is set to true", ->
      beforeEach ->
        atom.config.set("core.excludeVcsIgnoredPaths", true)

      describe "when the project's path is the repository's working directory", ->
        [ignoreFile, ignoredFile] = []

        beforeEach ->
          ignoreFile = path.join(atom.project.getPaths()[0], '.gitignore')
          fs.writeFileSync(ignoreFile, 'ignored.txt')

          ignoredFile = path.join(projectPath, 'ignored.txt')
          fs.writeFileSync(ignoredFile, 'ignored text')

          atom.config.set("core.excludeVcsIgnoredPaths", true)

        it "excludes paths that are git ignored", ->
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
          projectView.setMaxItems(Infinity)

          waitsFor ->
            projectView.list.children('li').length > 0

          runs ->
            expect(projectView.list.find("li:contains(ignored.txt)")).not.toExist()

      describe "when the project's path is a subfolder of the repository's working directory", ->
        [ignoreFile] = []

        beforeEach ->
          atom.project.setPaths([atom.project.resolve('dir')])
          ignoreFile = path.join(atom.project.getPaths()[0], '.gitignore')
          fs.writeFileSync(ignoreFile, 'b.txt')

        it "does not exclude paths that are git ignored", ->
          atom.commands.dispatch workspaceElement, 'fuzzy-finder:toggle-file-finder'
          projectView.setMaxItems(Infinity)

          waitsFor ->
            projectView.list.children('li').length > 0

          runs ->
            expect(projectView.list.find("li:contains(b.txt)")).toExist()
