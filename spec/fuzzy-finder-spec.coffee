{_, $, $$, fs, WorkspaceView} = require 'atom'
FuzzyFinder = require '../lib/fuzzy-finder-view'
PathLoader = require '../lib/path-loader'
path = require 'path'

describe 'FuzzyFinder', ->
  [finderView, workspaceView] = []

  beforeEach ->
    workspaceView = new WorkspaceView
    atom.workspaceView = workspaceView
    workspaceView.openSync('sample.js')
    workspaceView.enableKeymap()

    finderView = atom.packages.activatePackage("fuzzy-finder").mainModule.createView()

  describe "file-finder behavior", ->
    describe "toggling", ->
      describe "when the root view's project has a path", ->
        it "shows the FuzzyFinder or hides it and returns focus to the active editor if it already showing", ->
          workspaceView.attachToDom()
          expect(workspaceView.find('.fuzzy-finder')).not.toExist()
          workspaceView.getActiveView().splitRight()
          [editor1, editor2] = workspaceView.getEditorViews()

          expect(workspaceView.find('.fuzzy-finder')).not.toExist()
          workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
          expect(workspaceView.find('.fuzzy-finder')).toExist()
          expect(finderView.miniEditor.isFocused).toBeTruthy()
          expect(editor1.isFocused).toBeFalsy()
          expect(editor2.isFocused).toBeFalsy()
          finderView.miniEditor.insertText('this should not show up next time we toggle')

          workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
          expect(editor1.isFocused).toBeFalsy()
          expect(editor2.isFocused).toBeTruthy()
          expect(workspaceView.find('.fuzzy-finder')).not.toExist()

          workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
          expect(finderView.miniEditor.getText()).toBe ''

        it "shows all relative file paths for the current project and selects the first", ->
          workspaceView.attachToDom()
          finderView.maxItems = Infinity
          workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
          paths = null
          expect(finderView.find(".loading")).toBeVisible()
          expect(finderView.find(".loading").text().length).toBeGreaterThan 0

          waitsFor "all project paths to load", 5000, ->
            paths = finderView.projectPaths
            paths?.length > 0

          runs ->
            expect(paths.length).toBeGreaterThan 0
            expect(finderView.list.children('li').length).toBe paths.length
            for filePath in paths
              expect(finderView.list.find("li:contains(#{path.basename(filePath)})")).toExist()
            expect(finderView.list.children().first()).toHaveClass 'selected'
            expect(finderView.find(".loading")).not.toBeVisible()

        it "only creates a single path loader task", ->
          workspaceView.attachToDom()
          spyOn(PathLoader, 'startTask').andCallThrough()
          workspaceView.trigger 'fuzzy-finder:toggle-file-finder' # Show
          workspaceView.trigger 'fuzzy-finder:toggle-file-finder' # Hide
          workspaceView.trigger 'fuzzy-finder:toggle-file-finder' # Show again
          expect(PathLoader.startTask.callCount).toBe 1

        describe "symlinks on #darwin or #linux", ->
          beforeEach ->
            fs.symlinkSync(atom.project.resolve('sample.txt'), atom.project.resolve('symlink-to-file'))
            fs.symlinkSync(atom.project.resolve('dir'), atom.project.resolve('symlink-to-dir'))

          afterEach ->
            fs.unlinkSync(path.join(atom.project.getPath(), 'symlink-to-file'))
            fs.unlinkSync(path.join(atom.project.getPath(), 'symlink-to-dir'))

          it "includes symlinked file paths", ->
            workspaceView.attachToDom()
            finderView.maxItems = Infinity
            workspaceView.trigger 'fuzzy-finder:toggle-file-finder'

            waitsFor "all project paths to load", 5000, ->
              finderView.projectPaths?.length > 0

            runs ->
              expect(finderView.list.find("li:contains(symlink-to-file)")).toExist()

          it "excludes symlinked folder paths", ->
            workspaceView.attachToDom()
            finderView.maxItems = Infinity
            workspaceView.trigger 'fuzzy-finder:toggle-file-finder'

            waitsFor "all project paths to load", 5000, ->
              not finderView.reloadProjectPaths

            runs ->
              expect(finderView.list.find("li:contains(symlink-to-dir)")).not.toExist()

      describe "when root view's project has no path", ->
        beforeEach ->
          atom.project.setPath(null)

        it "does not open the FuzzyFinder", ->
          expect(workspaceView.find('.fuzzy-finder')).not.toExist()
          workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
          expect(workspaceView.find('.fuzzy-finder')).not.toExist()

    describe "when a path selection is confirmed", ->
      it "opens the file associated with that path in that split", ->
        workspaceView.attachToDom()
        editor1 = workspaceView.getActiveView()
        editor2 = editor1.splitRight()
        expect(workspaceView.getActiveView()).toBe editor2
        workspaceView.trigger 'fuzzy-finder:toggle-file-finder'

        expectedPath = atom.project.resolve('dir/a')
        finderView.confirmed({filePath: expectedPath})

        waitsFor ->
          workspaceView.getActivePane().getItems().length == 2

        runs ->
          editor3 = workspaceView.getActiveView()
          expect(finderView.hasParent()).toBeFalsy()
          expect(editor1.getPath()).not.toBe expectedPath
          expect(editor2.getPath()).not.toBe expectedPath
          expect(editor3.getPath()).toBe expectedPath
          expect(editor3.isFocused).toBeTruthy()

      describe "when the selected path is a directory", ->
        it "leaves the the tree view open, doesn't open the path in the editor, and displays an error", ->
          workspaceView.attachToDom()
          editorPath = workspaceView.getActiveView().getPath()
          workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
          finderView.confirmed({filePath: atom.project.resolve('dir')})
          expect(finderView.hasParent()).toBeTruthy()
          expect(workspaceView.getActiveView().getPath()).toBe editorPath
          expect(finderView.error.text().length).toBeGreaterThan 0
          advanceClock(2000)
          expect(finderView.error.text().length).toBe 0

  describe "buffer-finder behavior", ->
    describe "toggling", ->
      describe "when there are pane items with paths", ->
        beforeEach ->
          workspaceView.attachToDom()
          workspaceView.openSync('sample.txt')

        it "shows the FuzzyFinder if it isn't showing, or hides it and returns focus to the active editor", ->
          expect(workspaceView.find('.fuzzy-finder')).not.toExist()
          workspaceView.getActiveView().splitRight()
          [editor1, editor2, editor3] = workspaceView.getEditorViews()
          expect(workspaceView.getActiveView()).toBe editor3

          expect(editor1.isFocused).toBeFalsy()
          expect(editor2.isFocused).toBeFalsy()
          expect(editor3.isFocused).toBeTruthy()

          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          expect(workspaceView.find('.fuzzy-finder')).toExist()
          expect(workspaceView.find('.fuzzy-finder input:focus')).toExist()
          finderView.miniEditor.insertText('this should not show up next time we toggle')

          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          expect(editor1.isFocused).toBeFalsy()
          expect(editor2.isFocused).toBeFalsy()
          expect(editor3.isFocused).toBeTruthy()
          expect(workspaceView.find('.fuzzy-finder')).not.toExist()

          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          expect(finderView.miniEditor.getText()).toBe ''

        it "lists the paths of the current items, sorted by most recently opened but with the current item last", ->
          workspaceView.openSync 'sample-with-tabs.coffee'
          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          expect(_.pluck(finderView.list.find('li > div.file'), 'outerText')).toEqual ['sample.txt', 'sample.js', 'sample-with-tabs.coffee']
          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'

          workspaceView.openSync 'sample.txt'
          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'

          expect(_.pluck(finderView.list.find('li > div.file'), 'outerText')).toEqual ['sample-with-tabs.coffee', 'sample.js', 'sample.txt']
          expect(finderView.list.children().first()).toHaveClass 'selected'

        it "serializes the list of paths and their last opened time", ->
          workspaceView.openSync 'sample-with-tabs.coffee'
          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          workspaceView.openSync 'sample.js'
          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          workspaceView.openSync()

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
          workspaceView.getActivePane().remove()
          workspaceView.openSync()
          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          expect(workspaceView.find('.fuzzy-finder')).not.toExist()

      describe "when there are no pane items", ->
        it "does not open", ->
          workspaceView.getActivePane().remove()
          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          expect(workspaceView.find('.fuzzy-finder')).not.toExist()

      describe "when multiple sessions are opened on the same path", ->
        it "does not display duplicates for that path in the list", ->
          workspaceView.openSync 'sample.js'
          workspaceView.getActiveView().splitRight()
          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          expect(_.pluck(finderView.list.find('li > div.file'), 'outerText')).toEqual ['sample.js']

    describe "when a path selection is confirmed", ->
      [editor1, editor2, editor3] = []

      beforeEach ->
        workspaceView.attachToDom()
        editor1 = workspaceView.getActiveView()
        editor2 = editor1.splitRight()
        editor3 = workspaceView.openSync ('sample.txt')

        [editor1, editor2, editor3] = workspaceView.getEditorViews()

        expect(workspaceView.getActiveView()).toBe editor3

        editor2.trigger 'pane:show-previous-item'
        workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'

      describe "when the active pane has an item for the selected path", ->
        it "switches to the item for the selected path", ->
          expectedPath = atom.project.resolve('sample.txt')
          finderView.confirmed({filePath: expectedPath})

          waitsFor ->
            workspaceView.getActiveView().getPath() == expectedPath

          runs ->
            expect(finderView.hasParent()).toBeFalsy()
            expect(editor1.getPath()).not.toBe expectedPath
            expect(editor2.getPath()).not.toBe expectedPath
            expect(editor3.getPath()).toBe expectedPath
            expect(editor3.isFocused).toBeTruthy()

      describe "when the active pane does not have an item for the selected path", ->
        it "adds a new item to the active pane for the selcted path", ->
          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          editor1.focus()
          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'

          expect(workspaceView.getActiveView()).toBe editor1

          expectedPath = atom.project.resolve('sample.txt')
          finderView.confirmed({filePath: expectedPath})

          waitsFor ->
            workspaceView.getActivePane().getItems().length == 2

          runs ->
            editor4 = workspaceView.getActiveView()

            expect(finderView.hasParent()).toBeFalsy()
            expect(editor1.isFocused).toBeFalsy()

            expect(editor4).not.toBe editor1
            expect(editor4).not.toBe editor2
            expect(editor4).not.toBe editor3

            expect(editor4.getPath()).toBe expectedPath
            expect(editor4.isFocused).toBeTruthy()

  describe "common behavior between file and buffer finder", ->
    describe "when the fuzzy finder is cancelled", ->
      describe "when an editor is open", ->
        it "detaches the finder and focuses the previously focused element", ->
          workspaceView.attachToDom()
          activeEditor = workspaceView.getActiveView()
          activeEditor.focus()

          workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
          expect(finderView.hasParent()).toBeTruthy()
          expect(activeEditor.isFocused).toBeFalsy()
          expect(finderView.miniEditor.isFocused).toBeTruthy()

          finderView.cancel()

          expect(finderView.hasParent()).toBeFalsy()
          expect(activeEditor.isFocused).toBeTruthy()
          expect(finderView.miniEditor.isFocused).toBeFalsy()

      describe "when no editors are open", ->
        it "detaches the finder and focuses the previously focused element", ->
          workspaceView.attachToDom()
          workspaceView.getActivePane().remove()

          inputView = $$ -> @input()
          workspaceView.append(inputView)
          inputView.focus()

          workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
          expect(finderView.hasParent()).toBeTruthy()
          expect(finderView.miniEditor.isFocused).toBeTruthy()

          finderView.cancel()

          expect(finderView.hasParent()).toBeFalsy()
          expect(document.activeElement).toBe inputView[0]
          expect(finderView.miniEditor.isFocused).toBeFalsy()

  describe "cached file paths", ->
    it "caches file paths after first time", ->
      spyOn(PathLoader, "startTask").andCallThrough()
      workspaceView.trigger 'fuzzy-finder:toggle-file-finder'

      waitsFor ->
        finderView.list.children('li').length > 0

      runs ->
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
        workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
        workspaceView.trigger 'fuzzy-finder:toggle-file-finder'

      waitsFor ->
        finderView.list.children('li').length > 0

      runs ->
        expect(PathLoader.startTask).not.toHaveBeenCalled()

    it "doesn't cache buffer paths", ->
      spyOn(atom.project, "getEditors").andCallThrough()
      workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'

      waitsFor ->
        finderView.list.children('li').length > 0

      runs ->
        expect(atom.project.getEditors).toHaveBeenCalled()
        atom.project.getEditors.reset()
        workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
        workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'

      waitsFor ->
        finderView.list.children('li').length > 0

      runs ->
        expect(atom.project.getEditors).toHaveBeenCalled()

    it "busts the cache when the window gains focus", ->
      spyOn(PathLoader, "startTask").andCallThrough()
      workspaceView.trigger 'fuzzy-finder:toggle-file-finder'

      waitsFor ->
        finderView.list.children('li').length > 0

      runs ->
        expect(PathLoader.startTask).toHaveBeenCalled()
        PathLoader.startTask.reset()
        $(window).triggerHandler 'focus'
        workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
        workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
        expect(PathLoader.startTask).toHaveBeenCalled()

  it "ignores paths that match entries in config.fuzzyFinder.ignoredNames", ->
    atom.config.set("fuzzyFinder.ignoredNames", ["tree-view.js"])
    workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
    finderView.maxItems = Infinity

    waitsFor ->
      finderView.list.children('li').length > 0

    runs ->
      expect(finderView.list.find("li:contains(tree-view.js)")).not.toExist()

  describe "opening a path into a split", ->
    it "opens the path by splitting the active editor left", ->
      expect(workspaceView.getPanes().length).toBe 1
      pane = workspaceView.getActivePane()
      spyOn(pane, "splitLeft").andCallThrough()

      workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
      {filePath} = finderView.getSelectedElement()
      finderView.miniEditor.trigger 'pane:split-left'

      waitsFor ->
        workspaceView.getPanes().length == 2

      runs ->
        expect(workspaceView.getPanes().length).toBe 2
        expect(pane.splitLeft).toHaveBeenCalled()
        expect(workspaceView.getActiveView().getPath()).toBe atom.project.resolve(filePath)

    it "opens the path by splitting the active editor right", ->
      expect(workspaceView.getPanes().length).toBe 1
      pane = workspaceView.getActivePane()
      spyOn(pane, "splitRight").andCallThrough()

      workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
      {filePath} = finderView.getSelectedElement()
      finderView.miniEditor.trigger 'pane:split-right'

      waitsFor ->
        workspaceView.getPanes().length == 2

      runs ->
        expect(workspaceView.getPanes().length).toBe 2
        expect(pane.splitRight).toHaveBeenCalled()
        expect(workspaceView.getActiveView().getPath()).toBe atom.project.resolve(filePath)

    it "opens the path by splitting the active editor up", ->
      expect(workspaceView.getPanes().length).toBe 1
      pane = workspaceView.getActivePane()
      spyOn(pane, "splitUp").andCallThrough()

      workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
      {filePath} = finderView.getSelectedElement()
      finderView.miniEditor.trigger 'pane:split-up'

      waitsFor ->
        workspaceView.getPanes().length == 2

      runs ->
        expect(workspaceView.getPanes().length).toBe 2
        expect(pane.splitUp).toHaveBeenCalled()
        expect(workspaceView.getActiveView().getPath()).toBe atom.project.resolve(filePath)

    it "opens the path by splitting the active editor down", ->
      expect(workspaceView.getPanes().length).toBe 1
      pane = workspaceView.getActivePane()
      spyOn(pane, "splitDown").andCallThrough()

      workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
      {filePath} = finderView.getSelectedElement()
      finderView.miniEditor.trigger 'pane:split-down'

      waitsFor ->
        workspaceView.getPanes().length == 2

      runs ->
        expect(workspaceView.getPanes().length).toBe 2
        expect(pane.splitDown).toHaveBeenCalled()
        expect(workspaceView.getActiveView().getPath()).toBe atom.project.resolve(filePath)

  describe "when the filter text contains a colon followed by a number", ->
    it "opens the selected path to that line number", ->
      workspaceView.attachToDom()
      expect(workspaceView.find('.fuzzy-finder')).not.toExist()
      [editor] = workspaceView.getEditorViews()
      expect(editor.getCursorBufferPosition()).toEqual [0, 0]

      workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
      expect(workspaceView.find('.fuzzy-finder')).toExist()
      finderView.miniEditor.insertText(':4')
      finderView.trigger 'core:confirm'
      spyOn(finderView, 'moveToLine').andCallThrough()

      waitsFor ->
        finderView.moveToLine.callCount > 0

      runs ->
        finderView.moveToLine.reset()
        expect(editor.getCursorBufferPosition()).toEqual [3, 4]

        workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
        expect(workspaceView.find('.fuzzy-finder')).toExist()
        finderView.miniEditor.insertText(':10')
        finderView.miniEditor.trigger 'pane:split-left'

      waitsFor ->
        finderView.moveToLine.callCount > 0

      runs ->
        expect(workspaceView.getActiveView()).not.toBe editor
        expect(workspaceView.getActiveView().getCursorBufferPosition()).toEqual [9, 2]


  describe "Git integration", ->
    [projectPath] = []

    beforeEach ->
      projectPath = atom.project.resolve('git/working-dir')
      fs.moveSync(path.join(projectPath, 'git.git'), path.join(projectPath, '.git'))
      atom.project.setPath(projectPath)

    afterEach ->
      fs.moveSync(path.join(projectPath, '.git'), path.join(projectPath, 'git.git'))

    describe "git-status-finder behavior", ->
      [originalText, originalPath, newPath] = []

      beforeEach ->
        workspaceView.openSync('a.txt')
        editor = workspaceView.getActiveView()
        originalText = editor.getText()
        originalPath = editor.getPath()
        fs.writeFileSync(originalPath, 'making a change for the better')
        atom.project.getRepo().getPathStatus(originalPath)

        newPath = atom.project.resolve('newsample.js')
        fs.writeFileSync(newPath, '')
        atom.project.getRepo().getPathStatus(newPath)

      afterEach ->
        fs.writeFileSync(originalPath, originalText)
        fs.removeSync(newPath)

      it "displays all new and modified paths", ->
        expect(workspaceView.find('.fuzzy-finder')).not.toExist()
        workspaceView.trigger 'fuzzy-finder:toggle-git-status-finder'
        expect(workspaceView.find('.fuzzy-finder')).toExist()

        expect(finderView.find('.file').length).toBe 2

        expect(finderView.find('.status.status-modified').length).toBe 1
        expect(finderView.find('.status.status-added').length).toBe 1

    describe "status decorations", ->
      [originalText, originalPath, editor, newPath] = []

      beforeEach ->
        workspaceView.attachToDom()
        workspaceView.openSync('a.txt')
        editor = workspaceView.getActiveView()
        originalText = editor.getText()
        originalPath = editor.getPath()
        newPath = atom.project.resolve('newsample.js')
        fs.writeFileSync(newPath, '')

      afterEach ->
        fs.writeFileSync(originalPath, originalText)
        fs.removeSync(newPath)

      describe "when a modified file is shown in the list", ->
        it "displays the modified icon", ->
          editor.setText('modified')
          editor.save()
          atom.project.getRepo().getPathStatus(editor.getPath())

          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          expect(finderView.find('.status.status-modified').length).toBe 1
          expect(finderView.find('.status.status-modified').closest('li').find('.file').text()).toBe 'a.txt'

      describe "when a new file is shown in the list", ->
        it "displays the new icon", ->
          workspaceView.openSync('newsample.js')
          editor = workspaceView.getActiveView()
          atom.project.getRepo().getPathStatus(editor.getPath())

          workspaceView.trigger 'fuzzy-finder:toggle-buffer-finder'
          expect(finderView.find('.status.status-added').length).toBe 1
          expect(finderView.find('.status.status-added').closest('li').find('.file').text()).toBe 'newsample.js'

    describe "when core.excludeVcsIgnoredPaths is set to true", ->
      beforeEach ->
        atom.config.set("core.excludeVcsIgnoredPaths", true)

      describe "when the project's path is the repository's working directory", ->
        [ignoreFile, ignoredFile] = []

        beforeEach ->
          ignoreFile = path.join(atom.project.getPath(), '.gitignore')
          fs.writeFileSync(ignoreFile, 'ignored.txt')

          ignoredFile = path.join(projectPath, 'ignored.txt')
          fs.writeFileSync(ignoredFile, 'ignored text')

          atom.config.set("core.excludeVcsIgnoredPaths", true)

        afterEach ->
          fs.removeSync(ignoredFile)
          fs.removeSync(ignoreFile)

        it "excludes paths that are git ignored", ->
          workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
          finderView.maxItems = Infinity

          waitsFor ->
            finderView.list.children('li').length > 0

          runs ->
            expect(finderView.list.find("li:contains(ignored.txt)")).not.toExist()

      describe "when the project's path is a subfolder of the repository's working directory", ->
        [ignoreFile] = []

        beforeEach ->
          atom.project.setPath(atom.project.resolve('dir'))
          ignoreFile = path.join(atom.project.getPath(), '.gitignore')
          fs.writeFileSync(ignoreFile, 'b.txt')

        afterEach ->
          fs.removeSync(ignoreFile)

        it "does not exclude paths that are git ignored", ->
          workspaceView.trigger 'fuzzy-finder:toggle-file-finder'
          finderView.maxItems = Infinity

          waitsFor ->
            finderView.list.children('li').length > 0

          runs ->
            expect(finderView.list.find("li:contains(b.txt)")).toExist()
